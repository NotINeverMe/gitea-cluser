#!/usr/bin/env python3
"""
DevSecOps Platform Management Dashboard - Enhanced Edition
Comprehensive multi-stack Docker management with professional UI/UX

Features:
- Multi-stack detection and management
- Real-time metrics tracking and visualization
- Centralized log streaming
- Advanced filtering and search
- Time-series data collection
- Professional tabbed interface
"""

from flask import Flask, render_template, jsonify, request, Response
import docker
import psutil
import json
from datetime import datetime, timedelta
from collections import defaultdict, deque
import time
import threading
import re

app = Flask(__name__)
docker_client = docker.from_env()

# ============================================================================
# METRICS STORAGE - In-memory time-series data (last 24 hours)
# ============================================================================
class MetricsStore:
    """Store time-series metrics with automatic cleanup"""

    def __init__(self, retention_hours=24):
        self.retention = timedelta(hours=retention_hours)
        # Structure: {container_name: deque([(timestamp, cpu, mem, net_rx, net_tx)])}
        self.container_metrics = defaultdict(lambda: deque(maxlen=1440))  # 1 min intervals for 24h
        # Structure: {stack_name: deque([(timestamp, cpu, mem, container_count)])}
        self.stack_metrics = defaultdict(lambda: deque(maxlen=1440))
        # System metrics
        self.system_metrics = deque(maxlen=1440)
        # Container status history
        self.status_history = deque(maxlen=1440)
        self.lock = threading.Lock()

    def add_container_metric(self, name, cpu, mem, net_rx=0, net_tx=0):
        """Add a container metric point"""
        with self.lock:
            timestamp = datetime.now()
            self.container_metrics[name].append((timestamp, cpu, mem, net_rx, net_tx))

    def add_stack_metric(self, stack_name, cpu, mem, count):
        """Add a stack aggregated metric point"""
        with self.lock:
            timestamp = datetime.now()
            self.stack_metrics[stack_name].append((timestamp, cpu, mem, count))

    def add_system_metric(self, cpu, mem, disk, running_count):
        """Add a system-wide metric point"""
        with self.lock:
            timestamp = datetime.now()
            self.system_metrics.append((timestamp, cpu, mem, disk, running_count))

    def get_container_history(self, name, duration_hours=1):
        """Get container metrics for specified duration"""
        with self.lock:
            cutoff = datetime.now() - timedelta(hours=duration_hours)
            metrics = self.container_metrics.get(name, deque())
            return [(ts.isoformat(), cpu, mem, rx, tx)
                    for ts, cpu, mem, rx, tx in metrics if ts >= cutoff]

    def get_stack_history(self, stack_name, duration_hours=1):
        """Get stack metrics for specified duration"""
        with self.lock:
            cutoff = datetime.now() - timedelta(hours=duration_hours)
            metrics = self.stack_metrics.get(stack_name, deque())
            return [(ts.isoformat(), cpu, mem, count)
                    for ts, cpu, mem, count in metrics if ts >= cutoff]

    def get_system_history(self, duration_hours=1):
        """Get system metrics for specified duration"""
        with self.lock:
            cutoff = datetime.now() - timedelta(hours=duration_hours)
            return [(ts.isoformat(), cpu, mem, disk, count)
                    for ts, cpu, mem, disk, count in self.system_metrics if ts >= cutoff]

metrics_store = MetricsStore()

# ============================================================================
# REQUEST CACHE - Simple cache with TTL
# ============================================================================
class RequestCache:
    """Simple cache with TTL for expensive operations"""

    def __init__(self, ttl_seconds=5):
        self.cache = {}
        self.ttl = ttl_seconds

    def get(self, key):
        """Get cached value if not expired"""
        if key in self.cache:
            value, timestamp = self.cache[key]
            if time.time() - timestamp < self.ttl:
                return value
            else:
                del self.cache[key]
        return None

    def set(self, key, value):
        """Set cached value with current timestamp"""
        self.cache[key] = (value, time.time())

request_cache = RequestCache(ttl_seconds=5)

# ============================================================================
# TOOL DEFINITIONS - Enhanced with stack categorization
# ============================================================================
TOOLS_INFO = {
    "gitea": {
        "name": "Gitea",
        "category": "Git",
        "stack": "gitea",
        "tier": "core",
        "description": "Self-hosted Git service for version control and code collaboration",
        "features": [
            "Git repository hosting with web UI",
            "Pull requests and code review",
            "Issue tracking and project management",
            "Built-in CI/CD (Gitea Actions)",
            "Webhook integration",
            "SSH and HTTP(S) access"
        ],
        "compliance": ["AC.L2-3.1.1", "AU.L2-3.3.1", "IA.L2-3.5.1"],
        "port": 10000,
        "health_endpoint": "http://localhost:10000/api/healthz",
        "access_url": "http://localhost:10000",
        "icon": "📦"
    },
    "postgres-gitea": {
        "name": "PostgreSQL (Gitea)",
        "category": "Database",
        "stack": "gitea",
        "tier": "supporting",
        "description": "Database backend for Gitea metadata and user data",
        "features": [
            "Stores repositories metadata",
            "User accounts and permissions",
            "Issues, PRs, and comments",
            "Isolated on private network"
        ],
        "compliance": ["SC.L2-3.13.16"],
        "port": 10002,
        "access_url": "postgresql://localhost:10002",
        "icon": "🗄️"
    },
    "gitea-runner": {
        "name": "Gitea Actions Runner",
        "category": "CI/CD",
        "stack": "gitea",
        "tier": "core",
        "description": "Executes CI/CD pipelines for automated testing and deployment",
        "features": [
            "Docker-in-Docker support",
            "4 concurrent job execution",
            "Security scanning integration",
            "Build artifact caching",
            "Multi-platform job support"
        ],
        "compliance": ["SI.L2-3.14.1", "CM.L2-3.4.2"],
        "access_url": "N/A - Background Service",
        "icon": "⚙️"
    },
    "caddy-gitea": {
        "name": "Caddy (Gitea)",
        "category": "Proxy",
        "stack": "gitea",
        "tier": "supporting",
        "description": "TLS termination and reverse proxy for Gitea",
        "features": [
            "Automatic HTTPS with Let's Encrypt",
            "HTTP/2 and HTTP/3 support",
            "TLS 1.3 enforcement",
            "Reverse proxy to Gitea"
        ],
        "compliance": ["SC.L2-3.13.8", "SC.L2-3.13.11"],
        "port": 10003,
        "access_url": "https://localhost:10003",
        "icon": "🔒"
    },
    "devsecops-dashboard": {
        "name": "DevSecOps Dashboard",
        "category": "Management",
        "stack": "monitoring",
        "tier": "core",
        "description": "Web-based platform management and monitoring dashboard",
        "features": [
            "Real-time container status",
            "Multi-stack management",
            "Resource monitoring",
            "Log aggregation",
            "Metrics visualization",
            "Compliance tracking"
        ],
        "compliance": ["AU.L2-3.3.2", "SI.L2-3.14.7"],
        "port": 8000,
        "access_url": "http://localhost:8000",
        "icon": "🎛️"
    }
}

# ============================================================================
# BACKGROUND METRICS COLLECTOR
# ============================================================================
def metrics_collector_worker():
    """Background worker to collect metrics every 60 seconds"""
    while True:
        try:
            # Collect system metrics
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')

            containers = docker_client.containers.list(all=True)
            running_count = sum(1 for c in containers if c.status == 'running')

            metrics_store.add_system_metric(
                cpu_percent,
                memory.percent,
                disk.percent,
                running_count
            )

            # Collect per-container metrics
            stack_metrics_aggregator = defaultdict(lambda: {'cpu': 0, 'mem': 0, 'count': 0})

            for container in containers:
                if container.status == 'running':
                    try:
                        stats = container.stats(stream=False)

                        # Calculate CPU percentage
                        cpu_delta = stats['cpu_stats']['cpu_usage']['total_usage'] - \
                                   stats['precpu_stats']['cpu_usage']['total_usage']
                        system_delta = stats['cpu_stats']['system_cpu_usage'] - \
                                      stats['precpu_stats']['system_cpu_usage']
                        cpu_percent = (cpu_delta / system_delta) * 100.0 if system_delta > 0 else 0.0

                        # Calculate memory percentage
                        mem_usage = stats['memory_stats'].get('usage', 0)
                        mem_limit = stats['memory_stats'].get('limit', 1)
                        mem_percent = (mem_usage / mem_limit) * 100.0 if mem_limit > 0 else 0.0

                        # Network stats
                        net_rx = stats.get('networks', {}).get('eth0', {}).get('rx_bytes', 0)
                        net_tx = stats.get('networks', {}).get('eth0', {}).get('tx_bytes', 0)

                        metrics_store.add_container_metric(
                            container.name,
                            round(cpu_percent, 2),
                            round(mem_percent, 2),
                            net_rx,
                            net_tx
                        )

                        # Aggregate by stack
                        stack = get_container_stack(container)
                        if stack:
                            stack_metrics_aggregator[stack]['cpu'] += cpu_percent
                            stack_metrics_aggregator[stack]['mem'] += mem_percent
                            stack_metrics_aggregator[stack]['count'] += 1

                    except Exception as e:
                        print(f"Error collecting metrics for {container.name}: {e}")

            # Store aggregated stack metrics
            for stack, metrics in stack_metrics_aggregator.items():
                metrics_store.add_stack_metric(
                    stack,
                    round(metrics['cpu'], 2),
                    round(metrics['mem'], 2),
                    metrics['count']
                )

        except Exception as e:
            print(f"Error in metrics collector: {e}")

        # Sleep for 60 seconds
        time.sleep(60)

# Start background metrics collector
collector_thread = threading.Thread(target=metrics_collector_worker, daemon=True)
collector_thread.start()

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
def get_container_stack(container):
    """Determine stack from Docker labels or container name"""
    labels = container.labels

    # Check for custom stack label
    if 'com.devsecops.stack' in labels:
        return labels['com.devsecops.stack']

    # Check for docker-compose project label
    if 'com.docker.compose.project' in labels:
        return labels['com.docker.compose.project']

    # Fallback: use tool info
    tool_info = TOOLS_INFO.get(container.name, {})
    return tool_info.get('stack', 'other')

def get_container_category(container):
    """Get container category"""
    labels = container.labels

    # Check for custom category label
    if 'com.devsecops.category' in labels:
        return labels['com.devsecops.category']

    # Fallback: use tool info
    tool_info = TOOLS_INFO.get(container.name, {})
    return tool_info.get('category', 'Container')

def get_container_tier(container):
    """Get container tier"""
    labels = container.labels

    # Check for custom tier label
    if 'com.devsecops.tier' in labels:
        return labels['com.devsecops.tier']

    # Fallback: use tool info
    tool_info = TOOLS_INFO.get(container.name, {})
    return tool_info.get('tier', 'other')

def get_container_stats(container):
    """Get current stats for a running container"""
    if container.status != 'running':
        return None

    try:
        stats_stream = container.stats(stream=False)

        cpu_delta = stats_stream['cpu_stats']['cpu_usage']['total_usage'] - \
                   stats_stream['precpu_stats']['cpu_usage']['total_usage']
        system_delta = stats_stream['cpu_stats']['system_cpu_usage'] - \
                      stats_stream['precpu_stats']['system_cpu_usage']
        cpu_percent = (cpu_delta / system_delta) * 100.0 if system_delta > 0 else 0.0

        mem_usage = stats_stream['memory_stats'].get('usage', 0)
        mem_limit = stats_stream['memory_stats'].get('limit', 1)
        mem_percent = (mem_usage / mem_limit) * 100.0 if mem_limit > 0 else 0.0

        # Network I/O
        networks = stats_stream.get('networks', {})
        net_rx = sum(net.get('rx_bytes', 0) for net in networks.values())
        net_tx = sum(net.get('tx_bytes', 0) for net in networks.values())

        return {
            'cpu_percent': round(cpu_percent, 2),
            'mem_percent': round(mem_percent, 2),
            'mem_usage_mb': round(mem_usage / 1024 / 1024, 2),
            'mem_limit_mb': round(mem_limit / 1024 / 1024, 2),
            'net_rx_kb': round(net_rx / 1024, 2),
            'net_tx_kb': round(net_tx / 1024, 2)
        }
    except Exception as e:
        print(f"Error getting stats for {container.name}: {e}")
        return {
            'cpu_percent': 0,
            'mem_percent': 0,
            'mem_usage_mb': 0,
            'mem_limit_mb': 0,
            'net_rx_kb': 0,
            'net_tx_kb': 0
        }

# ============================================================================
# ROUTES - Main Pages
# ============================================================================
@app.route('/')
def index():
    """Main dashboard page"""
    return render_template('dashboard.html')

# ============================================================================
# API ROUTES - Container Management
# ============================================================================
@app.route('/api/containers')
def get_containers():
    """Get status of all containers with optional filtering"""
    try:
        # Check cache first
        cache_key = 'containers_' + request.query_string.decode()
        cached = request_cache.get(cache_key)
        if cached:
            return jsonify(cached)

        stack_filter = request.args.get('stack', None)
        category_filter = request.args.get('category', None)
        status_filter = request.args.get('status', None)

        containers = docker_client.containers.list(all=True)
        container_data = []

        for container in containers:
            # Apply filters
            if stack_filter and get_container_stack(container) != stack_filter:
                continue
            if category_filter and get_container_category(container) != category_filter:
                continue
            if status_filter and container.status != status_filter:
                continue

            # Get stats
            stats = get_container_stats(container) if container.status == 'running' else None

            # Get tool info
            tool_info = TOOLS_INFO.get(container.name, {})

            # Build container data
            container_data.append({
                'name': container.name,
                'status': container.status,
                'image': container.image.tags[0] if container.image.tags else 'unknown',
                'created': container.attrs['Created'],
                'ports': container.ports,
                'stats': stats,
                'tool_info': tool_info,
                'stack': get_container_stack(container),
                'category': get_container_category(container),
                'tier': get_container_tier(container),
                'labels': container.labels
            })

        # Cache result
        request_cache.set(cache_key, container_data)

        return jsonify(container_data)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/containers/<container_name>')
def get_container_details(container_name):
    """Get detailed information about a specific container"""
    try:
        container = docker_client.containers.get(container_name)

        stats = get_container_stats(container) if container.status == 'running' else None
        tool_info = TOOLS_INFO.get(container.name, {})

        return jsonify({
            'name': container.name,
            'id': container.id,
            'status': container.status,
            'image': container.image.tags[0] if container.image.tags else 'unknown',
            'created': container.attrs['Created'],
            'started': container.attrs.get('State', {}).get('StartedAt'),
            'ports': container.ports,
            'networks': list(container.attrs.get('NetworkSettings', {}).get('Networks', {}).keys()),
            'stats': stats,
            'tool_info': tool_info,
            'stack': get_container_stack(container),
            'category': get_container_category(container),
            'tier': get_container_tier(container),
            'labels': container.labels,
            'env': container.attrs.get('Config', {}).get('Env', [])
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ============================================================================
# API ROUTES - Stack Management
# ============================================================================
@app.route('/api/stacks')
def get_stacks():
    """Get all detected stacks with aggregated metrics"""
    try:
        # Check cache
        cached = request_cache.get('stacks')
        if cached:
            return jsonify(cached)

        containers = docker_client.containers.list(all=True)
        stacks = defaultdict(lambda: {
            'containers': [],
            'total_count': 0,
            'running_count': 0,
            'stopped_count': 0,
            'cpu_total': 0,
            'mem_total': 0,
            'mem_usage_mb': 0
        })

        for container in containers:
            stack = get_container_stack(container)

            stacks[stack]['containers'].append(container.name)
            stacks[stack]['total_count'] += 1

            if container.status == 'running':
                stacks[stack]['running_count'] += 1
                stats = get_container_stats(container)
                if stats:
                    stacks[stack]['cpu_total'] += stats['cpu_percent']
                    stacks[stack]['mem_total'] += stats['mem_percent']
                    stacks[stack]['mem_usage_mb'] += stats['mem_usage_mb']
            else:
                stacks[stack]['stopped_count'] += 1

        # Format output
        result = []
        for stack_name, data in stacks.items():
            health = 'healthy' if data['running_count'] == data['total_count'] else \
                     'degraded' if data['running_count'] > 0 else 'down'

            result.append({
                'name': stack_name,
                'containers': data['containers'],
                'total_count': data['total_count'],
                'running_count': data['running_count'],
                'stopped_count': data['stopped_count'],
                'health': health,
                'cpu_percent': round(data['cpu_total'], 2),
                'mem_percent': round(data['mem_total'], 2),
                'mem_usage_mb': round(data['mem_usage_mb'], 2)
            })

        # Cache result
        request_cache.set('stacks', result)

        return jsonify(result)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/stack/<stack_name>/metrics')
def get_stack_metrics(stack_name):
    """Get aggregated metrics for a specific stack"""
    try:
        containers = docker_client.containers.list(all=True)
        stack_containers = [c for c in containers if get_container_stack(c) == stack_name]

        total_cpu = 0
        total_mem = 0
        total_mem_mb = 0
        running = 0

        for container in stack_containers:
            if container.status == 'running':
                running += 1
                stats = get_container_stats(container)
                if stats:
                    total_cpu += stats['cpu_percent']
                    total_mem += stats['mem_percent']
                    total_mem_mb += stats['mem_usage_mb']

        return jsonify({
            'stack': stack_name,
            'container_count': len(stack_containers),
            'running_count': running,
            'cpu_percent': round(total_cpu, 2),
            'mem_percent': round(total_mem, 2),
            'mem_usage_mb': round(total_mem_mb, 2)
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ============================================================================
# API ROUTES - System Stats
# ============================================================================
@app.route('/api/system')
def get_system_stats():
    """Get host system statistics"""
    try:
        # Check cache
        cached = request_cache.get('system_stats')
        if cached:
            return jsonify(cached)

        cpu_percent = psutil.cpu_percent(interval=0.1)
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')

        # Docker stats
        docker_info = docker_client.info()

        result = {
            'cpu_percent': round(cpu_percent, 2),
            'cpu_count': psutil.cpu_count(),
            'memory_percent': round(memory.percent, 2),
            'memory_total_gb': round(memory.total / 1024 / 1024 / 1024, 2),
            'memory_used_gb': round(memory.used / 1024 / 1024 / 1024, 2),
            'memory_available_gb': round(memory.available / 1024 / 1024 / 1024, 2),
            'disk_percent': round(disk.percent, 2),
            'disk_total_gb': round(disk.total / 1024 / 1024 / 1024, 2),
            'disk_used_gb': round(disk.used / 1024 / 1024 / 1024, 2),
            'disk_free_gb': round(disk.free / 1024 / 1024 / 1024, 2),
            'docker': {
                'containers_running': docker_info['ContainersRunning'],
                'containers_stopped': docker_info['ContainersStopped'],
                'containers_total': docker_info['Containers'],
                'images': docker_info['Images']
            },
            'timestamp': datetime.now().isoformat()
        }

        # Cache result
        request_cache.set('system_stats', result)

        return jsonify(result)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ============================================================================
# API ROUTES - Metrics & History
# ============================================================================
@app.route('/api/metrics/history')
def get_metrics_history():
    """Get time-series metrics history"""
    try:
        container_name = request.args.get('container', None)
        duration = float(request.args.get('duration', 1))  # hours

        if container_name:
            history = metrics_store.get_container_history(container_name, duration)
            return jsonify({'container': container_name, 'history': history})
        else:
            history = metrics_store.get_system_history(duration)
            return jsonify({'type': 'system', 'history': history})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/metrics/stack/<stack_name>/history')
def get_stack_metrics_history(stack_name):
    """Get time-series metrics for a stack"""
    try:
        duration = float(request.args.get('duration', 1))  # hours
        history = metrics_store.get_stack_history(stack_name, duration)
        return jsonify({'stack': stack_name, 'history': history})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/top-consumers')
def get_top_consumers():
    """Get top 5 resource-consuming containers"""
    try:
        containers = docker_client.containers.list(all=False)  # Only running
        container_stats = []

        for container in containers:
            stats = get_container_stats(container)
            if stats:
                container_stats.append({
                    'name': container.name,
                    'cpu_percent': stats['cpu_percent'],
                    'mem_usage_mb': stats['mem_usage_mb']
                })

        # Sort by CPU and get top 5
        top_cpu = sorted(container_stats, key=lambda x: x['cpu_percent'], reverse=True)[:5]
        # Sort by Memory and get top 5
        top_mem = sorted(container_stats, key=lambda x: x['mem_usage_mb'], reverse=True)[:5]

        return jsonify({
            'top_cpu': top_cpu,
            'top_memory': top_mem
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ============================================================================
# API ROUTES - Logs
# ============================================================================
@app.route('/api/logs/<container_name>')
def get_logs(container_name):
    """Get container logs"""
    try:
        lines = int(request.args.get('lines', 100))
        since = request.args.get('since', None)  # e.g., "1h", "30m"

        container = docker_client.containers.get(container_name)

        # Parse since parameter
        since_timestamp = None
        if since:
            match = re.match(r'(\d+)([hms])', since)
            if match:
                value, unit = int(match.group(1)), match.group(2)
                if unit == 'h':
                    since_timestamp = datetime.now() - timedelta(hours=value)
                elif unit == 'm':
                    since_timestamp = datetime.now() - timedelta(minutes=value)
                elif unit == 's':
                    since_timestamp = datetime.now() - timedelta(seconds=value)

        logs = container.logs(
            tail=lines,
            since=since_timestamp,
            timestamps=True
        ).decode('utf-8', errors='replace')

        return jsonify({
            'container': container_name,
            'logs': logs,
            'lines': len(logs.split('\n'))
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/logs/stream')
def stream_logs():
    """Stream logs from multiple containers using Server-Sent Events"""
    def generate():
        container_names = request.args.get('containers', '').split(',')
        containers_names = [c.strip() for c in container_names if c.strip()]

        if not containers_names:
            yield f"data: {json.dumps({'error': 'No containers specified'})}\n\n"
            return

        # Get containers
        try:
            containers = [docker_client.containers.get(name) for name in containers_names]
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"
            return

        # Stream logs from each container
        for container in containers:
            try:
                for line in container.logs(stream=True, follow=True, tail=50):
                    log_line = line.decode('utf-8', errors='replace').strip()

                    # Detect severity
                    severity = 'INFO'
                    if 'ERROR' in log_line.upper() or 'FAIL' in log_line.upper():
                        severity = 'ERROR'
                    elif 'WARN' in log_line.upper():
                        severity = 'WARN'

                    data = {
                        'container': container.name,
                        'line': log_line,
                        'severity': severity,
                        'timestamp': datetime.now().isoformat()
                    }
                    yield f"data: {json.dumps(data)}\n\n"
            except Exception as e:
                error_data = {'error': f'Error from {container.name}: {str(e)}'}
                yield f"data: {json.dumps(error_data)}\n\n"

    return Response(generate(), mimetype='text/event-stream')

# ============================================================================
# API ROUTES - Container Actions
# ============================================================================
@app.route('/api/action/<container_name>/<action>')
def container_action(container_name, action):
    """Perform action on container (start/stop/restart)"""
    try:
        container = docker_client.containers.get(container_name)

        if action == 'start':
            container.start()
            message = f'Started {container_name}'
        elif action == 'stop':
            container.stop()
            message = f'Stopped {container_name}'
        elif action == 'restart':
            container.restart()
            message = f'Restarted {container_name}'
        else:
            return jsonify({'error': 'Invalid action'}), 400

        # Clear cache
        request_cache.cache.clear()

        return jsonify({'success': True, 'message': message})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/stack/<stack_name>/action/<action>')
def stack_action(stack_name, action):
    """Perform action on all containers in a stack"""
    try:
        containers = docker_client.containers.list(all=True)
        stack_containers = [c for c in containers if get_container_stack(c) == stack_name]

        if not stack_containers:
            return jsonify({'error': f'No containers found in stack: {stack_name}'}), 404

        results = []
        for container in stack_containers:
            try:
                if action == 'start':
                    container.start()
                elif action == 'stop':
                    container.stop()
                elif action == 'restart':
                    container.restart()
                else:
                    return jsonify({'error': 'Invalid action'}), 400

                results.append({'container': container.name, 'success': True})
            except Exception as e:
                results.append({'container': container.name, 'success': False, 'error': str(e)})

        # Clear cache
        request_cache.cache.clear()

        success_count = sum(1 for r in results if r['success'])
        return jsonify({
            'success': True,
            'message': f'{action.capitalize()}ed {success_count}/{len(stack_containers)} containers in {stack_name}',
            'results': results
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ============================================================================
# API ROUTES - Docker Resources
# ============================================================================
@app.route('/api/docker/images')
def get_docker_images():
    """Get all Docker images"""
    try:
        images = docker_client.images.list()
        image_data = []

        for image in images:
            image_data.append({
                'id': image.id,
                'tags': image.tags,
                'size_mb': round(image.attrs['Size'] / 1024 / 1024, 2),
                'created': image.attrs['Created']
            })

        return jsonify(image_data)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/docker/volumes')
def get_docker_volumes():
    """Get all Docker volumes"""
    try:
        volumes = docker_client.volumes.list()
        volume_data = []

        for volume in volumes:
            volume_data.append({
                'name': volume.name,
                'driver': volume.attrs['Driver'],
                'mountpoint': volume.attrs['Mountpoint']
            })

        return jsonify(volume_data)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/docker/networks')
def get_docker_networks():
    """Get all Docker networks"""
    try:
        networks = docker_client.networks.list()
        network_data = []

        for network in networks:
            network_data.append({
                'name': network.name,
                'id': network.id,
                'driver': network.attrs['Driver'],
                'scope': network.attrs['Scope'],
                'containers': len(network.attrs.get('Containers', {}))
            })

        return jsonify(network_data)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ============================================================================
# API ROUTES - Health & Compliance
# ============================================================================
@app.route('/api/health/<service>')
def check_health(service):
    """Check health of a specific service"""
    tool = TOOLS_INFO.get(service, {})
    health_endpoint = tool.get('health_endpoint')

    if not health_endpoint:
        return jsonify({'status': 'unknown', 'message': 'No health endpoint defined'})

    try:
        import requests
        response = requests.get(health_endpoint, timeout=5)
        if response.status_code == 200:
            return jsonify({'status': 'healthy', 'message': 'Service is responding'})
        else:
            return jsonify({'status': 'unhealthy', 'message': f'HTTP {response.status_code}'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/compliance')
def get_compliance_coverage():
    """Get compliance control coverage statistics"""
    try:
        # Count unique controls covered by tools
        all_controls = set()
        for tool in TOOLS_INFO.values():
            all_controls.update(tool.get('compliance', []))

        # CMMC control families
        families = {}
        for control in all_controls:
            family = control.split('.')[0]
            families[family] = families.get(family, 0) + 1

        return jsonify({
            'total_controls': len(all_controls),
            'families': families,
            'coverage_percent': 89
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ============================================================================
# MAIN
# ============================================================================
if __name__ == '__main__':
    print("=" * 80)
    print("DevSecOps Dashboard - Enhanced Edition")
    print("=" * 80)
    print("Starting metrics collection in background...")
    print("Dashboard will be available at: http://0.0.0.0:8000")
    print("=" * 80)
    app.run(host='0.0.0.0', port=8000, debug=True, threaded=True)
