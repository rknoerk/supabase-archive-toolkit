#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Supabase Archive Toolkit - Backup ===${NC}"

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo -e "${RED}Error: .env file not found. Copy .env.example to .env and fill in your credentials.${NC}"
    exit 1
fi

# Validate required variables
if [ -z "$PROJECT_NAME" ] || [ -z "$DATABASE_URL" ] || [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_SERVICE_ROLE_KEY" ]; then
    echo -e "${RED}Error: Missing required environment variables. Check your .env file.${NC}"
    exit 1
fi

# Create backup directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="backups/${PROJECT_NAME}_${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

echo -e "${YELLOW}Backup directory: $BACKUP_DIR${NC}"

# Check for required tools
check_tool() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}Error: $1 is not installed.${NC}"
        echo "Install with: $2"
        exit 1
    fi
}

check_tool "pg_dump" "brew install postgresql"
check_tool "python3" "brew install python3"

# 1. Backup database schema
echo -e "\n${GREEN}[1/4] Backing up database schema...${NC}"
pg_dump "$DATABASE_URL" \
    --schema-only \
    --no-owner \
    --no-privileges \
    -f "$BACKUP_DIR/schema.sql"
echo "Schema saved to $BACKUP_DIR/schema.sql"

# 2. Backup database data
echo -e "\n${GREEN}[2/4] Backing up database data...${NC}"
pg_dump "$DATABASE_URL" \
    --data-only \
    --no-owner \
    --no-privileges \
    --exclude-table='auth.*' \
    --exclude-table='storage.*' \
    --exclude-table='supabase_*' \
    -f "$BACKUP_DIR/data.sql"
echo "Data saved to $BACKUP_DIR/data.sql"

# 3. Backup full database (schema + data combined)
echo -e "\n${GREEN}[3/4] Creating full database dump...${NC}"
pg_dump "$DATABASE_URL" \
    --no-owner \
    --no-privileges \
    -f "$BACKUP_DIR/full_backup.sql"
echo "Full backup saved to $BACKUP_DIR/full_backup.sql"

# 4. Backup storage files
echo -e "\n${GREEN}[4/4] Backing up storage files...${NC}"
BACKUP_DIR="$BACKUP_DIR" python3 scripts/backup-storage.py

# Save metadata
echo -e "\n${GREEN}Saving backup metadata...${NC}"
cat > "$BACKUP_DIR/metadata.json" << EOF
{
    "project_name": "$PROJECT_NAME",
    "supabase_url": "$SUPABASE_URL",
    "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "backup_tool_version": "1.0.0"
}
EOF

# Create archive
echo -e "\n${GREEN}Creating archive...${NC}"
cd backups
tar -czf "${PROJECT_NAME}_${TIMESTAMP}.tar.gz" "${PROJECT_NAME}_${TIMESTAMP}"
cd ..

echo -e "\n${GREEN}=== Backup Complete ===${NC}"
echo -e "Backup folder: ${YELLOW}$BACKUP_DIR${NC}"
echo -e "Archive: ${YELLOW}backups/${PROJECT_NAME}_${TIMESTAMP}.tar.gz${NC}"
echo -e "\nYou can now safely delete your Supabase project."
