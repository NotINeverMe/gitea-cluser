# DevSecOps Platform Management Dashboard

A beautiful dark-mode web dashboard for managing and monitoring your complete DevSecOps platform cluster.

## Features

### 📊 Real-Time Monitoring
- **System Statistics**: CPU, memory, disk usage with live progress bars
- **Container Status**: All 31 containers with health indicators
- **Resource Usage**: Per-container CPU and memory metrics
- **Auto-Refresh**: Updates every 5 seconds automatically

### 🔧 Container Management
- **Start/Stop/Restart**: Control containers with one click
- **Live Logs**: View last 100 lines of container logs
- **Health Checks**: Visual status indicators (running/stopped/exited)
- **Resource Stats**: Real-time CPU and memory usage per container

### 📚 Tool Documentation
- **Detailed Information**: Purpose and features of each tool
- **Security Scanners**: Overview of all 15+ scanning tools
- **Compliance Mapping**: CMMC 2.0 controls for each service
- **Integration Points**: How tools connect together

### ✅ Compliance Dashboard
- **89% Coverage**: CMMC 2.0 Level 2 automated controls
- **Control Families**: Breakdown by AC, AU, CM, IA, IR, SC, SI
- **Visual Progress**: Color-coded progress bars

## Quick Start

### Option 1: Docker Compose (Recommended)

```bash
cd /home/notme/Desktop/gitea/dashboard

# Build and start dashboard
docker-compose -f docker-compose-dashboard.yml up -d

# View logs
docker-compose -f docker-compose-dashboard.yml logs -f

# Access dashboard
# Open browser: http://localhost:8000
```

### Option 2: Python Directly

```bash
cd /home/notme/Desktop/gitea/dashboard

# Install dependencies
pip3 install -r requirements.txt

# Run dashboard
python3 app.py

# Access dashboard
# Open browser: http://localhost:8000
```

## Screenshots

### Main Dashboard
- System statistics cards showing containers, CPU, memory, compliance
- Color-coded progress bars
- Real-time updates every 5 seconds

### Containers Tab
- All 31 containers with detailed information
- Status badges (running/stopped)
- Resource usage metrics
- Start/Stop/Restart buttons
- View logs functionality

### Tools & Scanners Tab
- Security scanner documentation
- Tool purposes and capabilities
- What each scanner detects

### Compliance Tab
- CMMC 2.0 coverage percentage
- Control family breakdown
- Visual coverage metrics

## Dashboard Layout

```
┌─────────────────────────────────────────────────────────────┐
│  DevSecOps Platform Dashboard                               │
│  Last updated: HH:MM:SS                                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
│  │ 30/31    │  │ CPU 45%  │  │ Mem 62%  │  │ CMMC 89%  │  │
│  │ Running  │  │ 8 cores  │  │ 16GB     │  │ Coverage  │  │
│  └──────────┘  └──────────┘  └──────────┘  └───────────┘  │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  [Containers] [Tools & Scanners] [Compliance]               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  📦 Gitea                                  ✓ Running        │
│  Git Repository Server                                      │
│  ✓ Web UI  ✓ Actions  ✓ Webhooks                          │
│  AC.L2-3.1.1, AU.L2-3.3.1                                  │
│  CPU: 2.5%  Memory: 450MB                                  │
│  [Restart] [Stop] [Logs]                                   │
│                                                             │
│  🔍 SonarQube                              ✓ Running        │
│  SAST Security Scanner                                      │
│  ✓ OWASP Top 10  ✓ Quality Gates                          │
│  SI.L2-3.14.1, CA.L2-3.12.4                                │
│  CPU: 15.2%  Memory: 2.1GB                                 │
│  [Restart] [Stop] [Logs]                                   │
│                                                             │
│  ... (all 31 containers)                                    │
└─────────────────────────────────────────────────────────────┘
```

## API Endpoints

The dashboard exposes several REST API endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Dashboard UI |
| `/api/containers` | GET | List all containers with stats |
| `/api/system` | GET | Host system statistics |
| `/api/tools` | GET | Tool information and scanners |
| `/api/compliance` | GET | Compliance coverage stats |
| `/api/health/<service>` | GET | Health check for specific service |
| `/api/logs/<container>` | GET | Last 100 lines of container logs |
| `/api/action/<container>/<action>` | GET | Start/stop/restart container |

## Configuration

### Environment Variables

```bash
# Flask configuration
FLASK_ENV=production        # production or development
FLASK_DEBUG=False          # Enable debug mode

# Dashboard settings
REFRESH_INTERVAL=5         # Auto-refresh interval (seconds)
LOG_LINES=100             # Number of log lines to fetch
```

### Docker Socket Access

The dashboard needs access to the Docker socket to manage containers:

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
```

**Note**: Read-only (`:ro`) access is used for security.

## Security Considerations

1. **Docker Socket Access**: Dashboard has read-only access to Docker socket
2. **No Authentication**: Add reverse proxy with auth for production
3. **Network Isolation**: Connects only to `gitea_default` and `gitea_monitoring` networks
4. **Resource Limits**: CPU and memory limits prevent resource exhaustion
5. **Non-Root User**: Runs as UID 1000 (dashboard user)

## Adding to Production

### With TLS/Authentication (Recommended)

```yaml
# Add to docker-compose-dashboard.yml
services:
  caddy:
    image: caddy:2-alpine
    ports:
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
    depends_on:
      - dashboard
```

### Caddyfile Example

```caddyfile
dashboard.yourdomain.com {
    # Basic auth
    basicauth {
        admin $2a$14$... # bcrypt hash
    }

    reverse_proxy dashboard:8000
}
```

## Troubleshooting

### Dashboard Won't Start

```bash
# Check logs
docker-compose -f docker-compose-dashboard.yml logs dashboard

# Common issues:
# 1. Docker socket permission denied
sudo chmod 666 /var/run/docker.sock

# 2. Port already in use
sudo netstat -tulpn | grep 8000

# 3. Networks not found
docker network create gitea_default
docker network create gitea_monitoring
```

### Containers Not Showing

```bash
# Verify Docker access
docker ps

# Check dashboard logs for errors
docker logs devsecops-dashboard
```

### High Memory Usage

```bash
# Restart dashboard
docker-compose -f docker-compose-dashboard.yml restart dashboard

# Check resource limits
docker stats devsecops-dashboard
```

## Customization

### Add New Tool Information

Edit `app.py` and add to `TOOLS_INFO`:

```python
TOOLS_INFO = {
    "your-container": {
        "name": "Your Tool",
        "category": "Category",
        "description": "Description",
        "features": ["Feature 1", "Feature 2"],
        "compliance": ["AC.L2-3.1.1"],
        "port": 8080,
        "health_endpoint": "http://localhost:8080/health",
        "icon": "🔧"
    }
}
```

### Change Refresh Interval

Edit `dashboard.html` line ~500:

```javascript
// Change from 5000 (5 seconds) to desired interval
setInterval(refreshData, 10000); // 10 seconds
```

### Customize Colors

Edit `dashboard.html` CSS variables:

```css
:root {
    --bg-primary: #0d1117;
    --accent-blue: #58a6ff;
    /* ... customize all colors */
}
```

## Integration with Grafana

The dashboard complements Grafana:

| Dashboard | Grafana |
|-----------|---------|
| Container management | Historical metrics |
| Real-time status | Time-series graphs |
| Tool documentation | Custom dashboards |
| Quick actions | Long-term trends |
| Compliance overview | Detailed analytics |

Use both together for complete visibility!

## Future Enhancements

Planned features:

- [ ] Authentication and user management
- [ ] Container logs streaming (WebSocket)
- [ ] Custom alert configuration
- [ ] Multi-host cluster support
- [ ] Container deployment wizard
- [ ] Backup/restore management
- [ ] Webhook configuration UI
- [ ] Dark/Light theme toggle

## Contributing

To extend the dashboard:

1. Add new API endpoints in `app.py`
2. Update UI in `templates/dashboard.html`
3. Add tool definitions to `TOOLS_INFO`
4. Test with `python3 app.py`
5. Build Docker image: `docker build -t dashboard .`

## Support

- **Dashboard Issues**: Check `docker logs devsecops-dashboard`
- **API Errors**: Enable Flask debug mode
- **Performance**: Increase resource limits in docker-compose
- **Documentation**: See main platform docs in `/docs`

---

**Access Dashboard**: http://localhost:8000

**Default Credentials**: None (add authentication for production)

**Auto-Refresh**: Every 5 seconds

**Supported Browsers**: Chrome, Firefox, Safari, Edge (modern versions)
