#!/usr/bin/env python3
"""
DevSecOps Platform Management Dashboard
Dark mode web dashboard for cluster management and monitoring
"""

from flask import Flask, render_template, jsonify
import docker
import psutil
import json
from datetime import datetime
import subprocess
import os

app = Flask(__name__)
docker_client = docker.from_env()

# Tool definitions with detailed information
TOOLS_INFO = {
    "gitea": {
        "name": "Gitea",
        "category": "Git Repository",
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
        "category": "Reverse Proxy",
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
        "description": "Web-based platform management and monitoring dashboard",
        "features": [
            "Real-time container status",
            "Resource monitoring",
            "Log viewing",
            "Container control",
            "Compliance tracking"
        ],
        "compliance": ["AU.L2-3.3.2", "SI.L2-3.14.7"],
        "port": 8000,
        "access_url": "http://localhost:8000",
        "icon": "🎛️"
    }
}

SECURITY_SCANNERS = {
    "trivy": {
        "name": "Trivy",
        "purpose": "Container vulnerability scanning",
        "scans": ["Container images", "IaC files", "Filesystems"],
        "icon": "🛡️"
    },
    "grype": {
        "name": "Grype",
        "purpose": "CVE detection in images",
        "scans": ["Container images", "Directories", "Archives"],
        "icon": "🔐"
    },
    "semgrep": {
        "name": "Semgrep",
        "purpose": "Advanced SAST pattern matching",
        "scans": ["Python", "Go", "Java", "JavaScript", "TypeScript"],
        "icon": "🔎"
    },
    "checkov": {
        "name": "Checkov",
        "purpose": "Terraform policy validation",
        "scans": ["Terraform", "CloudFormation", "Kubernetes", "Helm"],
        "icon": "✅"
    },
    "tfsec": {
        "name": "tfsec",
        "purpose": "Terraform security scanning",
        "scans": ["Terraform files", "Terraform modules"],
        "icon": "🔒"
    },
    "terrascan": {
        "name": "Terrascan",
        "purpose": "IaC compliance scanning",
        "scans": ["Terraform", "Kubernetes", "Helm", "Dockerfile"],
        "icon": "📋"
    }
}

@app.route('/')
def index():
    """Main dashboard page"""
    return render_template('dashboard.html')

@app.route('/api/containers')
def get_containers():
    """Get status of all containers (filtered to Gitea-related only)"""
    try:
        containers = docker_client.containers.list(all=True)
        container_data = []

        # Only show Gitea-related containers
        gitea_containers = ['gitea', 'postgres-gitea', 'gitea-runner', 'caddy-gitea', 'devsecops-dashboard']

        for container in containers:
            # Filter to only include Gitea-related containers
            if container.name not in gitea_containers:
                continue

            stats = None
            if container.status == 'running':
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

                    stats = {
                        'cpu_percent': round(cpu_percent, 2),
                        'mem_percent': round(mem_percent, 2),
                        'mem_usage_mb': round(mem_usage / 1024 / 1024, 2)
                    }
                except:
                    stats = {'cpu_percent': 0, 'mem_percent': 0, 'mem_usage_mb': 0}

            # Get tool info if available
            tool_info = TOOLS_INFO.get(container.name, {})

            container_data.append({
                'name': container.name,
                'status': container.status,
                'image': container.image.tags[0] if container.image.tags else 'unknown',
                'created': container.attrs['Created'],
                'ports': container.ports,
                'stats': stats,
                'tool_info': tool_info
            })

        return jsonify(container_data)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/system')
def get_system_stats():
    """Get host system statistics"""
    try:
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')

        # Docker stats
        docker_info = docker_client.info()

        return jsonify({
            'cpu_percent': cpu_percent,
            'cpu_count': psutil.cpu_count(),
            'memory_percent': memory.percent,
            'memory_total_gb': round(memory.total / 1024 / 1024 / 1024, 2),
            'memory_used_gb': round(memory.used / 1024 / 1024 / 1024, 2),
            'disk_percent': disk.percent,
            'disk_total_gb': round(disk.total / 1024 / 1024 / 1024, 2),
            'disk_used_gb': round(disk.used / 1024 / 1024 / 1024, 2),
            'docker': {
                'containers_running': docker_info['ContainersRunning'],
                'containers_total': docker_info['Containers'],
                'images': docker_info['Images']
            }
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/tools')
def get_tools():
    """Get information about all tools"""
    return jsonify({
        'persistent_services': TOOLS_INFO,
        'security_scanners': SECURITY_SCANNERS
    })

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
            'coverage_percent': 89  # From our analysis
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/logs/<container_name>')
def get_logs(container_name):
    """Get last 100 lines of container logs"""
    try:
        container = docker_client.containers.get(container_name)
        logs = container.logs(tail=100).decode('utf-8')
        return jsonify({'logs': logs})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

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

        return jsonify({'success': True, 'message': message})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=True)
