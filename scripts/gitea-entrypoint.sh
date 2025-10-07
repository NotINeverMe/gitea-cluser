#!/bin/bash
# Gitea Custom Entrypoint
# Ensures admin user is created after Gitea starts

# Start Gitea in background
/usr/local/bin/docker-entrypoint.sh &
GITEA_PID=$!

# Wait for Gitea to be ready, then create admin user
/usr/local/bin/init-gitea-admin.sh &

# Wait for Gitea process
wait $GITEA_PID
