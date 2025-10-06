#!/bin/bash

# Dashboard Deployment and Troubleshooting Script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  DevSecOps Dashboard Deployment              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

cd "$(dirname "$0")"

# Check if Docker networks exist
echo -e "${YELLOW}→${NC} Checking Docker networks..."
if ! docker network inspect gitea_default >/dev/null 2>&1; then
    echo -e "${YELLOW}Creating gitea_default network...${NC}"
    docker network create gitea_default
fi

if ! docker network inspect gitea_monitoring >/dev/null 2>&1; then
    echo -e "${YELLOW}Creating gitea_monitoring network...${NC}"
    docker network create gitea_monitoring
fi

echo -e "${GREEN}✓${NC} Networks ready"
echo ""

# Check if running in Docker or native
echo -e "${YELLOW}Choose deployment method:${NC}"
echo "  1) Docker (recommended)"
echo "  2) Native Python (for testing)"
read -p "Enter choice [1-2]: " choice

if [ "$choice" = "1" ]; then
    echo ""
    echo -e "${BLUE}Deploying via Docker...${NC}"

    # Build image
    echo -e "${YELLOW}→${NC} Building Docker image..."
    docker build -t devsecops-dashboard:latest .

    # Stop existing container
    echo -e "${YELLOW}→${NC} Stopping existing container (if any)..."
    docker stop devsecops-dashboard 2>/dev/null || true
    docker rm devsecops-dashboard 2>/dev/null || true

    # Start container
    echo -e "${YELLOW}→${NC} Starting dashboard container..."
    docker-compose -f docker-compose-dashboard.yml up -d

    # Wait for startup
    echo -e "${YELLOW}→${NC} Waiting for dashboard to start..."
    sleep 5

    # Check status
    if docker ps | grep -q devsecops-dashboard; then
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  Dashboard Successfully Started!              ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}Access:${NC} http://localhost:8000"
        echo ""
        echo -e "${BLUE}Container Status:${NC}"
        docker ps --filter name=devsecops-dashboard --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        echo -e "${BLUE}View Logs:${NC} docker logs -f devsecops-dashboard"
        echo -e "${BLUE}Stop:${NC} docker stop devsecops-dashboard"
    else
        echo -e "${RED}✗ Container failed to start${NC}"
        echo ""
        echo "Checking logs:"
        docker logs devsecops-dashboard 2>&1 || true
    fi

elif [ "$choice" = "2" ]; then
    echo ""
    echo -e "${BLUE}Deploying natively with Python...${NC}"

    # Check Python
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}✗ Python 3 not found${NC}"
        exit 1
    fi

    # Install dependencies
    echo -e "${YELLOW}→${NC} Installing Python dependencies..."
    pip3 install -r requirements.txt --user

    # Check if port is available
    if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${RED}✗ Port 8000 is already in use${NC}"
        echo ""
        echo "Process using port 8000:"
        lsof -Pi :8000 -sTCP:LISTEN
        echo ""
        read -p "Kill this process? [y/N]: " kill_choice
        if [ "$kill_choice" = "y" ]; then
            lsof -Pi :8000 -sTCP:LISTEN -t | xargs kill -9
            echo -e "${GREEN}✓${NC} Port 8000 freed"
        else
            exit 1
        fi
    fi

    # Start dashboard
    echo -e "${YELLOW}→${NC} Starting dashboard on http://localhost:8000..."
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Dashboard Starting...                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Access:${NC} http://localhost:8000"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    echo ""

    python3 app.py
else
    echo -e "${RED}Invalid choice${NC}"
    exit 1
fi
