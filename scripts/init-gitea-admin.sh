#!/bin/bash
# Gitea Admin User Initialization Script
# This script ensures the admin user is created on container startup

set -e

# Wait for Gitea to be ready
echo "Waiting for Gitea to start..."
until curl -sf http://localhost:3000/api/healthz > /dev/null 2>&1; do
    sleep 2
done

echo "Gitea is ready, checking for admin user..."

# Check if admin user exists
ADMIN_EXISTS=$(gitea admin user list | grep -c "^${GITEA_ADMIN_USER:-admin}" || true)

if [ "$ADMIN_EXISTS" -eq 0 ]; then
    echo "Creating admin user: ${GITEA_ADMIN_USER:-admin}"
    gitea admin user create \
        --username "${GITEA_ADMIN_USER:-admin}" \
        --password "${GITEA_ADMIN_PASSWORD:-ChangeMe123!}" \
        --email "${GITEA_ADMIN_EMAIL:-admin@example.com}" \
        --admin \
        --must-change-password=false

    echo "✅ Admin user created successfully!"
else
    echo "ℹ️  Admin user already exists, skipping creation"
fi
