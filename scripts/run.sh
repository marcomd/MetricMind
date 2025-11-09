#!/bin/bash
# Git Productivity Analytics - Unified Execution Script
# Usage: ./scripts/run.sh [REPO_NAME] [OPTIONS]

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default behavior
DO_CLEAN=false
DO_EXTRACT=true
DO_LOAD=true
SINGLE_REPO=""
CONFIG_FILE="$PROJECT_DIR/config/repositories.json"
FROM_DATE=""
TO_DATE=""

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
Git Productivity Analytics - Unified Execution Script

Usage:
  $0 [REPO_NAME] [OPTIONS]

Arguments:
  REPO_NAME           Optional - Process only this repository (default: all enabled)

Options:
  --clean             Clean repository data before processing (prompts for confirmation)
  --skip-extraction   Skip git extraction, only load from existing JSON files
  --skip-load         Skip database loading, only extract to JSON files
  --from DATE         Start date for extraction (default: 6 months ago)
  --to DATE           End date for extraction (default: now)
  --config FILE       Configuration file (default: config/repositories.json)
  -h, --help          Show this help message

Examples:
  # Extract and load all enabled repositories
  $0

  # Process single repository
  $0 mater

  # Clean before processing (prompts for confirmation per repo)
  $0 --clean

  # Clean and process single repository
  $0 mater --clean

  # Only extract to JSON, don't load to database
  $0 --skip-load

  # Only load from existing JSON files
  $0 --skip-extraction

  # Custom date range
  $0 --from "1 month ago" --to "now"

  # Clean single repo with custom dates
  $0 mater --clean --from "2024-01-01" --to "2024-12-31"

Workflow:
  Without flags:     Extract from git → Load to database
  --clean:           Clean → Extract → Load (sequential per repo)
  --skip-extraction: Load from existing JSON files only
  --skip-load:       Extract to JSON files only

EOF
    exit 0
}

# Expand tilde in path
expand_path() {
    local path="$1"
    # Replace leading ~ with $HOME
    path="${path/#\~/$HOME}"
    echo "$path"
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        --clean)
            DO_CLEAN=true
            shift
            ;;
        --skip-extraction)
            DO_EXTRACT=false
            shift
            ;;
        --skip-load)
            DO_LOAD=false
            shift
            ;;
        --from)
            FROM_DATE="$2"
            shift 2
            ;;
        --to)
            TO_DATE="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -*)
            log_error "Unknown option: $1"
            echo "Run with --help for usage information"
            exit 1
            ;;
        *)
            # First non-option argument is repository name
            if [ -z "$SINGLE_REPO" ]; then
                SINGLE_REPO="$1"
            else
                log_error "Unexpected argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate flags
if [ "$DO_EXTRACT" = false ] && [ "$DO_LOAD" = false ]; then
    log_error "Cannot use both --skip-extraction and --skip-load (nothing to do!)"
    exit 1
fi

# Load environment variables if .env exists
if [ -f "$PROJECT_DIR/.env" ]; then
    log_info "Loading environment from .env"
    export $(grep -v '^#' "$PROJECT_DIR/.env" | xargs)
fi

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    log_error "jq is not installed. Please install it: brew install jq"
    exit 1
fi

# Read repository configuration
if [ -n "$SINGLE_REPO" ]; then
    # Filter for single repository
    REPOS=$(jq -r --arg repo "$SINGLE_REPO" '.repositories[] | select(.enabled == true and .name == $repo) | @json' "$CONFIG_FILE")

    if [ -z "$REPOS" ]; then
        log_error "Repository '$SINGLE_REPO' not found or not enabled in config"
        log_info "Available repositories:"
        jq -r '.repositories[].name' "$CONFIG_FILE" | while read name; do
            echo "  - $name"
        done
        exit 1
    fi

    log_info "Processing single repository: $SINGLE_REPO"
else
    # Process all enabled repositories
    REPOS=$(jq -r '.repositories[] | select(.enabled == true) | @json' "$CONFIG_FILE")
fi

# Use environment variables with defaults
OUTPUT_DIR=$(expand_path "${OUTPUT_DIR:-./data/exports}")

# Set date defaults if not provided
if [ -z "$FROM_DATE" ]; then
    FROM_DATE="${DEFAULT_FROM_DATE:-6 months ago}"
fi

if [ -z "$TO_DATE" ]; then
    TO_DATE="${DEFAULT_TO_DATE:-now}"
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Show execution plan
echo ""
echo "================================================================="
echo -e "${BLUE}Git Productivity Analytics - Execution Plan${NC}"
echo "================================================================="
log_info "Configuration: $CONFIG_FILE"
log_info "Output directory: $OUTPUT_DIR"
if [ "$DO_EXTRACT" = true ]; then
    log_info "Extraction period: $FROM_DATE to $TO_DATE"
fi
echo ""
log_info "Workflow:"
if [ "$DO_CLEAN" = true ]; then
    echo "  1. Clean repository data (with confirmation)"
fi
if [ "$DO_EXTRACT" = true ]; then
    echo "  ${DO_CLEAN:+2}$([[ "$DO_CLEAN" = false ]] && echo "1" || echo ""). Extract from git repositories"
fi
if [ "$DO_LOAD" = true ]; then
    if [ "$DO_CLEAN" = true ] && [ "$DO_EXTRACT" = true ]; then
        echo "  3. Load to database"
    elif [ "$DO_CLEAN" = true ] || [ "$DO_EXTRACT" = true ]; then
        echo "  2. Load to database"
    else
        echo "  1. Load to database"
    fi
fi
echo ""

# Count repositories
REPO_COUNT=$(echo "$REPOS" | wc -l | tr -d ' ')
log_info "Found $REPO_COUNT enabled repositories"
echo ""

# Initialize counters
SUCCESS_COUNT=0
ERROR_COUNT=0
TOTAL_COMMITS=0

# Save stdin on file descriptor 3 for use inside the loop
# (the loop consumes stdin, so we need to preserve it for interactive prompts)
exec 3<&0

# Process each repository
REPO_NUM=0
while IFS= read -r repo_json; do
    REPO_NUM=$((REPO_NUM + 1))

    REPO_NAME=$(echo "$repo_json" | jq -r '.name')
    REPO_PATH=$(expand_path "$(echo "$repo_json" | jq -r '.path')")
    REPO_DESC=$(echo "$repo_json" | jq -r '.description // "No description"')

    echo "================================================================="
    echo -e "${BLUE}Repository $REPO_NUM/$REPO_COUNT: $REPO_NAME${NC}"
    echo "Description: $REPO_DESC"
    echo "Path: $REPO_PATH"
    echo "================================================================="
    echo ""

    # Step 1: Clean (if requested)
    if [ "$DO_CLEAN" = true ]; then
        log_info "Step 1: Cleaning existing data for $REPO_NAME"
        echo ""

        # Use fd 3 (saved stdin) to allow interactive confirmation inside the loop
        if ! "$SCRIPT_DIR/clean_repository.rb" "$REPO_NAME" <&3; then
            log_error "Failed to clean repository data"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            echo ""
            continue
        fi

        echo ""
    fi

    # Check if repository path exists (only needed for extraction)
    if [ "$DO_EXTRACT" = true ]; then
        if [ ! -d "$REPO_PATH" ]; then
            log_error "Repository path does not exist: $REPO_PATH"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            echo ""
            continue
        fi

        # Check if it's a git repository
        if [ ! -d "$REPO_PATH/.git" ]; then
            log_error "Not a git repository: $REPO_PATH"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            echo ""
            continue
        fi
    fi

    # Generate output filename
    OUTPUT_FILE="$OUTPUT_DIR/${REPO_NAME}.json"

    # Step 2: Extract data from git (if not skipped)
    if [ "$DO_EXTRACT" = true ]; then
        STEP_NUM=$([[ "$DO_CLEAN" = true ]] && echo "2" || echo "1")
        log_info "Step $STEP_NUM: Extracting git data..."

        if "$PROJECT_DIR/scripts/git_extract_to_json.rb" "$FROM_DATE" "$TO_DATE" "$OUTPUT_FILE" "$REPO_NAME" "$REPO_PATH"; then
            log_success "Extraction complete"

            # Count commits in JSON file
            COMMITS=$(jq -r '.summary.total_commits' "$OUTPUT_FILE")
            log_info "Commits extracted: $COMMITS"
            echo ""
        else
            log_error "Extraction failed for $REPO_NAME"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            echo ""
            continue
        fi
    else
        # Verify JSON file exists for loading
        if [ "$DO_LOAD" = true ] && [ ! -f "$OUTPUT_FILE" ]; then
            log_error "JSON file not found: $OUTPUT_FILE"
            log_error "Cannot load data without extraction (use without --skip-extraction first)"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            echo ""
            continue
        fi
    fi

    # Step 3: Load data to database (if not skipped)
    if [ "$DO_LOAD" = true ]; then
        if [ "$DO_CLEAN" = true ] && [ "$DO_EXTRACT" = true ]; then
            STEP_NUM="3"
        elif [ "$DO_CLEAN" = true ] || [ "$DO_EXTRACT" = true ]; then
            STEP_NUM="2"
        else
            STEP_NUM="1"
        fi

        log_info "Step $STEP_NUM: Loading data to database..."

        if "$PROJECT_DIR/scripts/load_json_to_db.rb" "$OUTPUT_FILE"; then
            log_success "Data loaded successfully"

            # Count commits from JSON
            COMMITS=$(jq -r '.summary.total_commits' "$OUTPUT_FILE")
            TOTAL_COMMITS=$((TOTAL_COMMITS + COMMITS))

            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            log_error "Database load failed for $REPO_NAME"
            ERROR_COUNT=$((ERROR_COUNT + 1))
        fi
    else
        # Just count as success if we got here (extraction-only mode)
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    fi

    echo ""
done <<< "$REPOS"

# Post-processing steps (only if data was loaded)
if [ "$DO_LOAD" = true ] && [ $SUCCESS_COUNT -gt 0 ]; then
    echo "================================================================="
    echo -e "${BLUE}POST-PROCESSING${NC}"
    echo "================================================================="
    echo ""

    # Step 1: Categorize commits
    log_info "Step 1: Categorizing commits..."
    if "$SCRIPT_DIR/categorize_commits.rb" ${SINGLE_REPO:+--repo "$SINGLE_REPO"}; then
        log_success "Commits categorized"
    else
        log_warning "Categorization completed with warnings (this is normal if some commits couldn't be categorized)"
    fi
    echo ""

    # Step 2: Refresh materialized views
    log_info "Step 2: Refreshing materialized views..."
    if psql -d "${PGDATABASE:-git_analytics}" -c "SELECT refresh_all_mv(); SELECT refresh_category_mv();" > /dev/null 2>&1; then
        log_success "Materialized views refreshed"
    else
        log_warning "Failed to refresh materialized views (they may not exist yet)"
    fi
    echo ""
fi

# Final summary
echo "================================================================="
echo -e "${BLUE}FINAL SUMMARY${NC}"
echo "================================================================="
echo "Repositories processed:  $REPO_COUNT"
echo -e "${GREEN}Successful:${NC}              $SUCCESS_COUNT"
if [ $ERROR_COUNT -gt 0 ]; then
    echo -e "${RED}Errors:${NC}                  $ERROR_COUNT"
fi
if [ "$DO_LOAD" = true ]; then
    echo "Total commits loaded:    $TOTAL_COMMITS"
fi
echo "================================================================="

# Exit with error if any repository failed
if [ $ERROR_COUNT -gt 0 ]; then
    log_warning "Completed with $ERROR_COUNT error(s)"
    exit 1
else
    log_success "All repositories processed successfully!"
    exit 0
fi
