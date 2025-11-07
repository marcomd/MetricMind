#!/bin/bash
# Quick setup script for Git Productivity Analytics
# Usage: ./scripts/setup.sh

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Git Productivity Analytics Setup         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Check prerequisites
echo -e "${BLUE}[1/6] Checking prerequisites...${NC}"

# Check Ruby
if ! command -v ruby &> /dev/null; then
    echo -e "${RED}✗ Ruby is not installed${NC}"
    echo "  Please install Ruby >= 2.7"
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

# Step 2: Install Ruby dependencies
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

# Step 3: Create environment file
echo ""
echo -e "${BLUE}[3/6] Setting up environment configuration...${NC}"

if [ ! -f "$PROJECT_DIR/.env" ]; then
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
    echo -e "${GREEN}✓ Created .env file${NC}"
    echo -e "${YELLOW}  Please edit .env with your database credentials${NC}"
else
    echo -e "${YELLOW}⚠ .env already exists, skipping${NC}"
fi

# Load environment
if [ -f "$PROJECT_DIR/.env" ]; then
    export $(grep -v '^#' "$PROJECT_DIR/.env" | xargs)
fi

# Step 4: Create databases (production and test)
echo ""
echo -e "${BLUE}[4/6] Setting up databases...${NC}"

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

# Step 5: Initialize schema
echo ""
echo -e "${BLUE}[5/6] Initializing database schemas...${NC}"

# Initialize production database schema (if created or recreated)
if [ $PROD_DB_CREATED -eq 0 ]; then
    echo "  Initializing production database schema..."
    if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$PROJECT_DIR/schema/postgres_schema.sql" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Production schema initialized${NC}"
    else
        echo -e "${RED}✗ Failed to initialize production schema${NC}"
        exit 1
    fi

    if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$PROJECT_DIR/schema/postgres_views.sql" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Production views created${NC}"
    else
        echo -e "${RED}✗ Failed to create production views${NC}"
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

    if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_TEST_NAME" -f "$PROJECT_DIR/schema/postgres_views.sql" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Test views created${NC}"
    else
        echo -e "${RED}✗ Failed to create test views${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}  Skipping test schema (database not recreated)${NC}"
fi

# Step 6: Create directories
echo ""
echo -e "${BLUE}[6/6] Creating data directories...${NC}"

mkdir -p "$PROJECT_DIR/data/exports"
echo -e "${GREEN}✓ Created data/exports/${NC}"

# Final instructions
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Setup Complete!                           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Edit configuration:"
echo -e "   ${BLUE}vim config/repositories.json${NC}"
echo ""
echo "2. Extract and load data:"
echo -e "   ${BLUE}./scripts/run_extraction.sh${NC}"
echo ""
echo "3. Query the database:"
echo -e "   ${BLUE}psql -d $DB_NAME${NC}"
echo ""
echo "Examples:"
echo -e "   ${BLUE}# Single repo extraction${NC}"
echo -e "   ./scripts/git_extract_to_json.rb \"6 months ago\" \"now\" \"data/repo.json\""
echo ""
echo -e "   ${BLUE}# Load to database${NC}"
echo -e "   ./scripts/load_json_to_db.rb \"data/repo.json\""
echo ""
echo "Documentation: See DASHBOARD_README.md"
echo ""
