#!/bin/bash

# Load environment variables
source "$(dirname "$0")/.env"

DATE=$(date +"%Y-%m-%d_%H-%M")
BACKUP_FILE="${DB_NAME}_backup_${DATE}.sql.gz"
FULL_BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILE}"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Dump and compress PostgreSQL DB
pg_dump -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" "$DB_NAME" | gzip > "$FULL_BACKUP_PATH"

if [ $? -ne 0 ]; then
    echo "[ERROR] Backup failed"
    exit 1
fi

echo "[INFO] Backup created at $FULL_BACKUP_PATH"

# Upload to DigitalOcean Spaces using s3cmd
s3cmd put "$FULL_BACKUP_PATH" "s3://${DO_SPACE_BUCKET}/${DO_SPACE_PATH}${BACKUP_FILE}"

if [ $? -ne 0 ]; then
    echo "[ERROR] Upload to DigitalOcean Spaces failed"
    exit 1
fi

echo "[INFO] Uploaded to DO Spaces"

# Delete older local backups (keep only 3)
cd "$BACKUP_DIR"
ls -tp *.gz | grep -v '/$' | tail -n +4 | xargs -I {} rm -- {}

# Delete older backups from DO Spaces (keep only 3)
s3cmd ls "s3://${DO_SPACE_BUCKET}/${DO_SPACE_PATH}" | \
    sort -r | awk '{print $4}' | tail -n +4 | while read OLD_BACKUP; do
        echo "[INFO] Deleting old backup from DO Spaces: $OLD_BACKUP"
        s3cmd del "$OLD_BACKUP"
    done
