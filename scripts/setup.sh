#!/bin/bash
# Complete setup script for Git Productivity Analytics
# Usage: ./scripts/setup.sh [OPTIONS]
#
# Options:
#   --database-only    Only set up the database (skip dependencies and .env setup)
#   -h, --help         Show this help message

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Flags
DATABASE_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --database-only)
            DATABASE_ONLY=true
            shift
            ;;
        -h|--help)
            cat << EOF
Git Productivity Analytics - Setup Script

Usage:
  ./scripts/setup.sh [OPTIONS]

Options:
  --database-only    Only set up the database (skip dependencies and .env setup)
  -h, --help         Show this help message

Examples:
  # Full setup (recommended for first-time setup)
  ./scripts/setup.sh

  # Database-only setup (useful for recreating database)
  ./scripts/setup.sh --database-only

EOF
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run with --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Git Productivity Analytics Setup         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

if [ "$DATABASE_ONLY" = true ]; then
    echo -e "${YELLOW}Running in database-only mode${NC}"
    echo ""
fi

# Step 1: Check prerequisites
if [ "$DATABASE_ONLY" = false ]; then
    echo -e "${BLUE}[1/6] Checking prerequisites...${NC}"

    # Check Ruby
    if ! command -v ruby &> /dev/null; then
        echo -e "${RED}✗ Ruby is not installed${NC}"
        echo "  Please install Ruby >= 3.3"
        exit 1
    fi
    echo -e "${GREEN}✓ Ruby $(ruby --version | cut -d' ' -f2)${NC}"

    # Check PostgreSQL
    if ! command -v psql &> /dev/null; then
        echo -e "${RED}✗ PostgreSQL is not installed${NC}"
        echo "  Please install PostgreSQL >= 12"
        exit 1
    fi
    echo -e "${GREEN}✓ PostgreSQL $(psql --version | cut -d' ' -f3)${NC}"

    # Check jq
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}⚠ jq is not installed (needed for multi-repo orchestration)${NC}"
        echo "  Install with: brew install jq"
    else
        echo -e "${GREEN}✓ jq $(jq --version)${NC}"
    fi
else
    # Database-only mode: just check PostgreSQL
    echo -e "${BLUE}[1/3] Checking PostgreSQL...${NC}"
    if ! command -v psql &> /dev/null; then
        echo -e "${RED}✗ PostgreSQL is not installed${NC}"
        echo "  Please install PostgreSQL >= 12"
        exit 1
    fi
    echo -e "${GREEN}✓ PostgreSQL $(psql --version | cut -d' ' -f3)${NC}"
fi

# Step 2: Install Ruby dependencies (skip in database-only mode)
if [ "$DATABASE_ONLY" = false ]; then
    echo ""
    echo -e "${BLUE}[2/6] Installing Ruby dependencies...${NC}"
    cd "$PROJECT_DIR"

    if [ -f "Gemfile" ]; then
        if command -v bundle &> /dev/null; then
            bundle install
            echo -e "${GREEN}✓ Dependencies installed${NC}"
        else
            echo -e "${YELLOW}⚠ Bundler not found, installing...${NC}"
            gem install bundler
            bundle install
            echo -e "${GREEN}✓ Dependencies installed${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ No Gemfile found, skipping${NC}"
    fi
fi

# Step 3: Create environment file (skip in database-only mode)
if [ "$DATABASE_ONLY" = false ]; then
    echo ""
    echo -e "${BLUE}[3/6] Setting up environment configuration...${NC}"

    if [ ! -f "$PROJECT_DIR/.env" ]; then
        cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
        echo -e "${GREEN}✓ Created .env file${NC}"
        echo -e "${YELLOW}  Please edit .env with your database credentials${NC}"
    else
        echo -e "${YELLOW}⚠ .env already exists, skipping${NC}"
    fi
fi

# Load environment
if [ -f "$PROJECT_DIR/.env" ]; then
    export $(grep -v '^#' "$PROJECT_DIR/.env" | xargs)
fi

# Step 4/2: Create databases (production and test)
echo ""
if [ "$DATABASE_ONLY" = true ]; then
    echo -e "${BLUE}[2/3] Setting up databases...${NC}"
else
    echo -e "${BLUE}[4/6] Setting up databases...${NC}"
fi

DB_NAME="${PGDATABASE:-git_analytics}"
DB_TEST_NAME="${PGDATABASE_TEST:-${DB_NAME}_test}"
DB_USER="${PGUSER:-$USER}"
DB_HOST="${PGHOST:-localhost}"

echo "  Production DB: $DB_NAME"
echo "  Test DB: $DB_TEST_NAME"
echo "  Host: $DB_HOST"
echo "  User: $DB_USER"

# Function to create or recreate database
create_database() {
    local db_name=$1
    local db_label=$2

    if psql -h "$DB_HOST" -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$db_name"; then
        echo -e "${YELLOW}⚠ $db_label database '$db_name' already exists${NC}"
        read -p "  Do you want to recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            dropdb -h "$DB_HOST" -U "$DB_USER" "$db_name" 2>/dev/null || true
            createdb -h "$DB_HOST" -U "$DB_USER" "$db_name"
            echo -e "${GREEN}✓ $db_label database recreated${NC}"
            return 0
        else
            echo -e "${YELLOW}  Keeping existing $db_label database${NC}"
            return 1
        fi
    else
        createdb -h "$DB_HOST" -U "$DB_USER" "$db_name"
        echo -e "${GREEN}✓ $db_label database created${NC}"
        return 0
    fi
}

# Create production database
create_database "$DB_NAME" "Production"
PROD_DB_CREATED=$?

# Create test database
create_database "$DB_TEST_NAME" "Test"
TEST_DB_CREATED=$?

# Step 5/3: Initialize schema
echo ""
if [ "$DATABASE_ONLY" = true ]; then
    echo -e "${BLUE}[3/3] Initializing database schemas...${NC}"
else
    echo -e "${BLUE}[5/6] Initializing database schemas...${NC}"
fi

# Initialize production database schema (if created or recreated)
if [ $PROD_DB_CREATED -eq 0 ]; then
    echo "  Initializing production database schema..."
    if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$PROJECT_DIR/schema/postgres_schema.sql" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Production schema initialized${NC}"
    else
        echo -e "${RED}✗ Failed to initialize production schema${NC}"
        exit 1
    fi

    # Apply migrations
    echo "  Applying migrations..."
    MIGRATIONS_DIR="$PROJECT_DIR/schema/migrations"
    if [ -d "$MIGRATIONS_DIR" ]; then
        for migration in "$MIGRATIONS_DIR"/*.sql; do
            if [ -f "$migration" ]; then
                echo "    - Applying $(basename "$migration")..."
                if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$migration" > /dev/null 2>&1; then
                    echo -e "    ${GREEN}✓ $(basename "$migration")${NC}"
                else
                    echo -e "    ${RED}✗ Failed: $(basename "$migration")${NC}"
                    exit 1
                fi
            fi
        done
    fi

    if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$PROJECT_DIR/schema/postgres_views.sql" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Production standard views created${NC}"
    else
        echo -e "${RED}✗ Failed to create production views${NC}"
        exit 1
    fi

    if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$PROJECT_DIR/schema/category_views.sql" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Production category views created${NC}"
    else
        echo -e "${RED}✗ Failed to create category views${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}  Skipping production schema (database not recreated)${NC}"
fi

# Initialize test database schema (if created or recreated)
if [ $TEST_DB_CREATED -eq 0 ]; then
    echo "  Initializing test database schema..."
    if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_TEST_NAME" -f "$PROJECT_DIR/schema/postgres_schema.sql" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Test schema initialized${NC}"
    else
        echo -e "${RED}✗ Failed to initialize test schema${NC}"
        exit 1
    fi

    # Apply migrations to test database too
    echo "  Applying migrations to test database..."
    MIGRATIONS_DIR="$PROJECT_DIR/schema/migrations"
    if [ -d "$MIGRATIONS_DIR" ]; then
        for migration in "$MIGRATIONS_DIR"/*.sql; do
            if [ -f "$migration" ]; then
                if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_TEST_NAME" -f "$migration" > /dev/null 2>&1; then
                    echo -e "    ${GREEN}✓ $(basename "$migration")${NC}"
                else
                    echo -e "    ${YELLOW}⚠ Warning: $(basename "$migration") failed on test DB${NC}"
                fi
            fi
        done
    fi

    if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_TEST_NAME" -f "$PROJECT_DIR/schema/postgres_views.sql" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Test views created${NC}"
    else
        echo -e "${RED}✗ Failed to create test views${NC}"
        exit 1
    fi

    if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_TEST_NAME" -f "$PROJECT_DIR/schema/category_views.sql" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Test category views created${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Failed to create test category views${NC}"
    fi
else
    echo -e "${YELLOW}  Skipping test schema (database not recreated)${NC}"
fi

# Step 6: Create directories (skip in database-only mode)
if [ "$DATABASE_ONLY" = false ]; then
    echo ""
    echo -e "${BLUE}[6/6] Creating data directories...${NC}"

    mkdir -p "$PROJECT_DIR/data/exports"
    echo -e "${GREEN}✓ Created data/exports/${NC}"
fi

# Final instructions
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Setup Complete!                           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""

if [ "$DATABASE_ONLY" = true ]; then
    # Database-only mode instructions
    echo "Database setup complete!"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Configure repositories to track:"
    echo -e "   ${BLUE}vim config/repositories.json${NC}"
    echo ""
    echo "2. Extract and load data (with automatic categorization):"
    echo -e "   ${BLUE}./scripts/run.sh${NC}"
    echo ""
    echo "3. Query the database:"
    echo -e "   ${BLUE}psql -d $DB_NAME${NC}"
else
    # Full setup instructions
    echo "Next steps:"
    echo ""
    echo "1. Edit environment configuration (if needed):"
    echo -e "   ${BLUE}vim .env${NC}"
    echo ""
    echo "2. Configure repositories to track:"
    echo -e "   ${BLUE}vim config/repositories.json${NC}"
    echo ""
    echo "3. Extract and load data (with automatic categorization):"
    echo -e "   ${BLUE}./scripts/run.sh${NC}"
    echo ""
    echo "   This will:"
    echo "   - Extract git data from all enabled repositories"
    echo "   - Load data to database"
    echo "   - Categorize commits (extract business domains)"
    echo "   - Refresh materialized views"
    echo ""
    echo "4. Query the database:"
    echo -e "   ${BLUE}psql -d $DB_NAME${NC}"
fi

echo ""
echo "Useful commands:"
echo -e "   ${BLUE}# Process single repository${NC}"
echo -e "   ./scripts/run.sh mater"
echo ""
echo -e "   ${BLUE}# Custom date range${NC}"
echo -e "   ./scripts/run.sh --from \"1 year ago\" --to \"now\""
echo ""
echo -e "   ${BLUE}# Check categorization coverage${NC}"
echo -e "   psql -d $DB_NAME -c \"SELECT * FROM v_category_stats;\""
echo ""
echo "Documentation: See README.md"
echo ""
