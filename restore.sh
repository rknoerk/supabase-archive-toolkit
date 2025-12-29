#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Supabase Archive Toolkit - Restore ===${NC}"

# Check for backup path argument
if [ -z "$1" ]; then
    echo -e "${YELLOW}Available backups:${NC}"
    ls -la backups/*.tar.gz 2>/dev/null || echo "No backup archives found."
    echo ""
    ls -d backups/*/ 2>/dev/null || echo "No backup folders found."
    echo -e "\n${CYAN}Usage: ./restore.sh <backup-folder-or-archive>${NC}"
    echo "Example: ./restore.sh backups/my-app_20240115_120000"
    echo "Example: ./restore.sh backups/my-app_20240115_120000.tar.gz"
    exit 1
fi

BACKUP_PATH="$1"

# If it's a tar.gz, extract it first
if [[ "$BACKUP_PATH" == *.tar.gz ]]; then
    echo -e "${YELLOW}Extracting archive...${NC}"
    EXTRACT_DIR=$(dirname "$BACKUP_PATH")
    tar -xzf "$BACKUP_PATH" -C "$EXTRACT_DIR"
    BACKUP_PATH="${BACKUP_PATH%.tar.gz}"
    echo "Extracted to: $BACKUP_PATH"
fi

# Verify backup exists
if [ ! -d "$BACKUP_PATH" ]; then
    echo -e "${RED}Error: Backup directory not found: $BACKUP_PATH${NC}"
    exit 1
fi

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo -e "${RED}Error: .env file not found.${NC}"
    echo -e "${YELLOW}Create a .env file with your NEW Supabase project credentials.${NC}"
    exit 1
fi

# Validate required variables
if [ -z "$DATABASE_URL" ] || [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_SERVICE_ROLE_KEY" ]; then
    echo -e "${RED}Error: Missing required environment variables.${NC}"
    echo "Make sure your .env file contains:"
    echo "  - DATABASE_URL (for new project)"
    echo "  - SUPABASE_URL (for new project)"
    echo "  - SUPABASE_SERVICE_ROLE_KEY (for new project)"
    exit 1
fi

# Check for required tools
if ! command -v psql &> /dev/null; then
    echo -e "${RED}Error: psql is not installed. Install with: brew install postgresql${NC}"
    exit 1
fi

echo -e "\n${CYAN}Restore Configuration:${NC}"
echo "  Backup: $BACKUP_PATH"
echo "  Target: $SUPABASE_URL"
echo ""

# Confirmation
read -p "This will restore data to the target Supabase project. Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# 1. Restore database schema
if [ -f "$BACKUP_PATH/schema.sql" ]; then
    echo -e "\n${GREEN}[1/3] Restoring database schema...${NC}"
    psql "$DATABASE_URL" -f "$BACKUP_PATH/schema.sql" 2>&1 | grep -v "already exists" || true
    echo "Schema restored."
else
    echo -e "\n${YELLOW}[1/3] No schema.sql found, skipping schema restore.${NC}"
fi

# 2. Restore database data
if [ -f "$BACKUP_PATH/data.sql" ]; then
    echo -e "\n${GREEN}[2/3] Restoring database data...${NC}"
    psql "$DATABASE_URL" -f "$BACKUP_PATH/data.sql" 2>&1 || true
    echo "Data restored."
else
    echo -e "\n${YELLOW}[2/3] No data.sql found, skipping data restore.${NC}"
fi

# 3. Restore storage files
if [ -d "$BACKUP_PATH/storage" ]; then
    echo -e "\n${GREEN}[3/3] Restoring storage files...${NC}"
    BACKUP_DIR="$BACKUP_PATH" node scripts/restore-storage.js
else
    echo -e "\n${YELLOW}[3/3] No storage backup found, skipping storage restore.${NC}"
fi

echo -e "\n${GREEN}=== Restore Complete ===${NC}"
echo -e "\n${CYAN}Next steps:${NC}"
echo "1. Update your app's environment variables with new Supabase credentials:"
echo "   - SUPABASE_URL=$SUPABASE_URL"
echo "   - SUPABASE_ANON_KEY=(find in Dashboard → Settings → API)"
echo "2. Test your application"
echo "3. If using Lovable, update the Supabase connection in the app settings"
