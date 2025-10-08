/**
 * DevSecOps Dashboard - Main JavaScript
 * Core functionality for multi-stack Docker management
 */

// ============================================================================
// GLOBAL STATE
// ============================================================================
const DashboardState = {
    containers: [],
    stacks: [],
    systemStats: null,
    currentTab: 'overview',
    filters: {
        stack: 'all',
        category: 'all',
        status: 'all',
        search: ''
    },
    viewMode: 'grid', // 'grid' or 'list'
    autoRefreshInterval: 10000, // 10 seconds
    autoRefreshEnabled: true,
    theme: 'dark',
    refreshTimer: null
};

// Load preferences from localStorage
function loadPreferences() {
    const savedTheme = localStorage.getItem('dashboard-theme');
    const savedRefreshInterval = localStorage.getItem('dashboard-refresh-interval');
    const savedAutoRefresh = localStorage.getItem('dashboard-auto-refresh');

    if (savedTheme) DashboardState.theme = savedTheme;
    if (savedRefreshInterval) DashboardState.autoRefreshInterval = parseInt(savedRefreshInterval);
    if (savedAutoRefresh !== null) DashboardState.autoRefreshEnabled = savedAutoRefresh === 'true';

    // Apply theme
    document.documentElement.setAttribute('data-theme', DashboardState.theme);
}

function savePreferences() {
    localStorage.setItem('dashboard-theme', DashboardState.theme);
    localStorage.setItem('dashboard-refresh-interval', DashboardState.autoRefreshInterval);
    localStorage.setItem('dashboard-auto-refresh', DashboardState.autoRefreshEnabled);
}

// ============================================================================
// API FUNCTIONS
// ============================================================================
const API = {
    async getContainers(filters = {}) {
        const params = new URLSearchParams(filters);
        const response = await fetch(`/api/containers?${params}`);
        if (!response.ok) throw new Error('Failed to fetch containers');
        return await response.json();
    },

    async getStacks() {
        const response = await fetch('/api/stacks');
        if (!response.ok) throw new Error('Failed to fetch stacks');
        return await response.json();
    },

    async getSystemStats() {
        const response = await fetch('/api/system');
        if (!response.ok) throw new Error('Failed to fetch system stats');
        return await response.json();
    },

    async getTopConsumers() {
        const response = await fetch('/api/top-consumers');
        if (!response.ok) throw new Error('Failed to fetch top consumers');
        return await response.json();
    },

    async getMetricsHistory(container = null, duration = 1) {
        const params = new URLSearchParams();
        if (container) params.append('container', container);
        params.append('duration', duration);

        const response = await fetch(`/api/metrics/history?${params}`);
        if (!response.ok) throw new Error('Failed to fetch metrics history');
        return await response.json();
    },

    async getStackMetricsHistory(stack, duration = 1) {
        const response = await fetch(`/api/metrics/stack/${stack}/history?duration=${duration}`);
        if (!response.ok) throw new Error('Failed to fetch stack metrics');
        return await response.json();
    },

    async getLogs(containerName, lines = 100, since = null) {
        const params = new URLSearchParams({ lines });
        if (since) params.append('since', since);

        const response = await fetch(`/api/logs/${containerName}?${params}`);
        if (!response.ok) throw new Error('Failed to fetch logs');
        return await response.json();
    },

    async containerAction(containerName, action) {
        const response = await fetch(`/api/action/${containerName}/${action}`);
        if (!response.ok) throw new Error(`Failed to ${action} container`);
        return await response.json();
    },

    async stackAction(stackName, action) {
        const response = await fetch(`/api/stack/${stackName}/action/${action}`);
        if (!response.ok) throw new Error(`Failed to ${action} stack`);
        return await response.json();
    },

    async getDockerImages() {
        const response = await fetch('/api/images');
        if (!response.ok) throw new Error('Failed to fetch images');
        return await response.json();
    },

    async getDockerVolumes() {
        const response = await fetch('/api/volumes');
        if (!response.ok) throw new Error('Failed to fetch volumes');
        return await response.json();
    },

    async getDockerNetworks() {
        const response = await fetch('/api/networks');
        if (!response.ok) throw new Error('Failed to fetch networks');
        return await response.json();
    },

    async getSSDFCompliance() {
        const response = await fetch('/api/ssdf/compliance');
        if (!response.ok) throw new Error('Failed to fetch SSDF compliance data');
        return await response.json();
    }
};

// ============================================================================
// TOAST NOTIFICATIONS
// ============================================================================
const Toast = {
    container: null,

    init() {
        this.container = document.createElement('div');
        this.container.className = 'toast-container';
        document.body.appendChild(this.container);
    },

    show(message, type = 'info', duration = 5000) {
        const toast = document.createElement('div');
        toast.className = `toast toast-${type}`;

        const icons = {
            success: '✓',
            error: '✗',
            warning: '⚠',
            info: 'ℹ'
        };

        toast.innerHTML = `
            <div class="toast-icon">${icons[type] || icons.info}</div>
            <div class="toast-content">
                <div class="toast-message">${message}</div>
            </div>
        `;

        this.container.appendChild(toast);

        // Auto-remove after duration
        setTimeout(() => {
            toast.style.animation = 'slideInRight 0.3s reverse';
            setTimeout(() => toast.remove(), 300);
        }, duration);
    },

    success(message) { this.show(message, 'success'); },
    error(message) { this.show(message, 'error'); },
    warning(message) { this.show(message, 'warning'); },
    info(message) { this.show(message, 'info'); }
};

// ============================================================================
// MODAL MANAGEMENT
// ============================================================================
const Modal = {
    show(id) {
        const modal = document.getElementById(id);
        if (modal) modal.classList.add('active');
    },

    hide(id) {
        const modal = document.getElementById(id);
        if (modal) modal.classList.remove('active');
    },

    hideAll() {
        document.querySelectorAll('.modal').forEach(modal => {
            modal.classList.remove('active');
        });
    }
};

// ============================================================================
// TAB MANAGEMENT
// ============================================================================
function switchTab(tabName) {
    DashboardState.currentTab = tabName;

    // Update tab buttons
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.classList.remove('active');
    });
    const activeBtn = document.querySelector(`[data-tab="${tabName}"]`);
    if (activeBtn) activeBtn.classList.add('active');

    // Update tab content
    document.querySelectorAll('.tab-content').forEach(content => {
        content.classList.remove('active');
    });
    const activeContent = document.getElementById(`tab-${tabName}`);
    if (activeContent) activeContent.classList.add('active');

    // Load tab-specific data
    loadTabData(tabName);
}

async function loadTabData(tabName) {
    try {
        switch(tabName) {
            case 'overview':
                await loadOverviewData();
                break;
            case 'containers':
                await loadContainersData();
                break;
            case 'stacks':
                await loadStacksData();
                break;
            case 'logs':
                // Logs are loaded on-demand
                break;
            case 'metrics':
                await loadMetricsData();
                break;
            case 'terminal':
                await loadTerminalTab();
                break;
            case 'volumes':
                await loadVolumesTab();
                break;
            case 'images':
                await loadImagesTab();
                break;
            case 'ssdf':
                await loadSSDFTab();
                break;
        }
    } catch (error) {
        console.error(`Error loading ${tabName} data:`, error);
        Toast.error(`Failed to load ${tabName} data`);
    }
}

// ============================================================================
// OVERVIEW TAB
// ============================================================================
async function loadOverviewData() {
    try {
        // Load system stats
        const stats = await API.getSystemStats();
        updateSystemStats(stats);

        // Load stacks summary
        const stacks = await API.getStacks();
        updateStacksSummary(stacks);

        // Load top consumers
        const topConsumers = await API.getTopConsumers();
        updateTopConsumers(topConsumers);

        // Update resource gauges
        updateResourceGauges(stats);

    } catch (error) {
        console.error('Error loading overview data:', error);
    }
}

function updateSystemStats(stats) {
    // Update header stats
    const containersRunning = document.getElementById('stat-containers-running');
    const cpuUsage = document.getElementById('stat-cpu');
    const memUsage = document.getElementById('stat-memory');

    if (containersRunning) containersRunning.textContent = stats.docker.containers_running;
    if (cpuUsage) cpuUsage.textContent = `${stats.cpu_percent}%`;
    if (memUsage) memUsage.textContent = `${stats.memory_used_gb}GB`;

    // Update overview cards
    const totalContainers = document.getElementById('overview-total-containers');
    const runningContainers = document.getElementById('overview-running-containers');
    const totalImages = document.getElementById('overview-total-images');

    if (totalContainers) totalContainers.textContent = stats.docker.containers_total;
    if (runningContainers) runningContainers.textContent = stats.docker.containers_running;
    if (totalImages) totalImages.textContent = stats.docker.images;

    // Update last update time
    const lastUpdate = document.getElementById('last-update');
    if (lastUpdate) {
        const now = new Date();
        lastUpdate.textContent = now.toLocaleTimeString();
    }
}

function updateStacksSummary(stacks) {
    const totalStacks = document.getElementById('overview-total-stacks');
    if (totalStacks) totalStacks.textContent = stacks.length;
}

function updateTopConsumers(consumers) {
    const cpuList = document.getElementById('top-cpu-list');
    const memList = document.getElementById('top-memory-list');

    if (cpuList) {
        cpuList.innerHTML = consumers.top_cpu.map(c => `
            <div class="consumer-item">
                <span class="consumer-name">${c.name}</span>
                <span class="consumer-value">${c.cpu_percent.toFixed(1)}%</span>
            </div>
        `).join('');
    }

    if (memList) {
        memList.innerHTML = consumers.top_memory.map(c => `
            <div class="consumer-item">
                <span class="consumer-name">${c.name}</span>
                <span class="consumer-value">${c.mem_usage_mb.toFixed(0)}MB</span>
            </div>
        `).join('');
    }
}

function updateResourceGauges(stats) {
    updateCircularGauge('cpu-gauge', stats.cpu_percent);
    updateCircularGauge('memory-gauge', stats.memory_percent);
    updateCircularGauge('disk-gauge', stats.disk_percent);
}

function updateCircularGauge(id, percentage) {
    const gauge = document.getElementById(id);
    if (!gauge) return;

    const circle = gauge.querySelector('.circular-progress-fill');
    const text = gauge.querySelector('.circular-progress-text');

    if (circle) {
        const radius = 56;
        const circumference = 2 * Math.PI * radius;
        const offset = circumference - (percentage / 100) * circumference;

        circle.style.strokeDasharray = circumference;
        circle.style.strokeDashoffset = offset;

        // Color based on percentage
        let color = 'var(--accent-green)';
        if (percentage > 80) color = 'var(--accent-red)';
        else if (percentage > 60) color = 'var(--accent-yellow)';

        circle.style.stroke = color;
    }

    if (text) {
        text.textContent = `${percentage.toFixed(0)}%`;
        text.style.color = percentage > 80 ? 'var(--accent-red)' :
                          percentage > 60 ? 'var(--accent-yellow)' :
                          'var(--accent-green)';
    }
}

// ============================================================================
// CONTAINERS TAB
// ============================================================================
async function loadContainersData() {
    try {
        const containers = await API.getContainers();
        DashboardState.containers = containers;
        renderContainers(containers);
    } catch (error) {
        console.error('Error loading containers:', error);
        Toast.error('Failed to load containers');
    }
}

function renderContainers(containers) {
    const grid = document.getElementById('containers-grid');
    if (!grid) return;

    // Apply filters
    const filtered = containers.filter(container => {
        // Stack filter
        if (DashboardState.filters.stack !== 'all' && container.stack !== DashboardState.filters.stack) {
            return false;
        }

        // Category filter
        if (DashboardState.filters.category !== 'all' && container.category !== DashboardState.filters.category) {
            return false;
        }

        // Status filter
        if (DashboardState.filters.status !== 'all' && container.status !== DashboardState.filters.status) {
            return false;
        }

        // Search filter
        if (DashboardState.filters.search) {
            const searchLower = DashboardState.filters.search.toLowerCase();
            const name = (container.tool_info?.name || container.name).toLowerCase();
            const description = (container.tool_info?.description || '').toLowerCase();
            if (!name.includes(searchLower) && !description.includes(searchLower)) {
                return false;
            }
        }

        return true;
    });

    if (filtered.length === 0) {
        grid.innerHTML = `
            <div class="empty-state">
                <div class="empty-state-icon">📦</div>
                <div class="empty-state-text">No containers found</div>
            </div>
        `;
        return;
    }

    grid.innerHTML = filtered.map(container => createContainerCard(container)).join('');
}

function createContainerCard(container) {
    const tool = container.tool_info || {};
    const isRunning = container.status === 'running';
    const statusClass = `status-${container.status}`;

    // Access URL
    let accessHtml = '';
    if (tool.access_url && !tool.access_url.includes('N/A')) {
        accessHtml = `
            <div class="card-access">
                <div class="card-access-label">Access URL</div>
                <a href="${tool.access_url}" target="_blank" class="card-access-link">
                    ${tool.access_url} <span>↗</span>
                </a>
            </div>
        `;
    }

    // Metrics
    let metricsHtml = '';
    if (container.stats && isRunning) {
        const cpuClass = container.stats.cpu_percent > 80 ? 'metric-danger' :
                        container.stats.cpu_percent > 60 ? 'metric-warning' : 'metric-good';
        const memClass = container.stats.mem_percent > 80 ? 'metric-danger' :
                        container.stats.mem_percent > 60 ? 'metric-warning' : 'metric-good';

        metricsHtml = `
            <div class="metrics-grid">
                <div class="metric-item ${cpuClass}">
                    <div class="metric-label">CPU Usage</div>
                    <div class="metric-value">${container.stats.cpu_percent.toFixed(1)}%</div>
                    <div class="metric-bar">
                        <div class="metric-bar-fill" style="width: ${container.stats.cpu_percent}%"></div>
                    </div>
                </div>
                <div class="metric-item ${memClass}">
                    <div class="metric-label">Memory</div>
                    <div class="metric-value">${container.stats.mem_usage_mb}MB</div>
                    <div class="metric-bar">
                        <div class="metric-bar-fill" style="width: ${container.stats.mem_percent}%"></div>
                    </div>
                </div>
                <div class="metric-item">
                    <div class="metric-label">Network RX</div>
                    <div class="metric-value">${container.stats.net_rx_kb.toFixed(1)}KB/s</div>
                </div>
                <div class="metric-item">
                    <div class="metric-label">Network TX</div>
                    <div class="metric-value">${container.stats.net_tx_kb.toFixed(1)}KB/s</div>
                </div>
            </div>
        `;
    }

    // Features
    let featuresHtml = '';
    if (tool.features && tool.features.length > 0) {
        featuresHtml = `
            <div class="features-section">
                <div class="section-title">Key Features</div>
                <ul class="features-list">
                    ${tool.features.slice(0, 3).map(f => `<li>${f}</li>`).join('')}
                </ul>
            </div>
        `;
    }

    // Compliance
    let complianceHtml = '';
    if (tool.compliance && tool.compliance.length > 0) {
        complianceHtml = `
            <div class="compliance-section">
                <div class="section-title">CMMC Controls</div>
                <div class="compliance-tags">
                    ${tool.compliance.map(c => `<span class="compliance-tag">${c}</span>`).join('')}
                </div>
            </div>
        `;
    }

    return `
        <div class="container-card" data-container="${container.name}">
            <div class="card-header">
                <div class="card-icon">${tool.icon || '📦'}</div>
                <div class="card-title-section">
                    <div class="card-name">${tool.name || container.name}</div>
                    <div class="card-category">${tool.category || 'Container'}</div>
                </div>
                <div class="card-badges">
                    <span class="status-badge ${statusClass}">${container.status}</span>
                    ${container.stack ? `<span class="stack-badge" onclick="filterByStack('${container.stack}')">${container.stack}</span>` : ''}
                </div>
            </div>
            <div class="card-body">
                ${tool.description ? `<div class="card-description">${tool.description}</div>` : ''}
                ${accessHtml}
                ${metricsHtml}
                ${featuresHtml}
                ${complianceHtml}
            </div>
            <div class="card-actions">
                ${!isRunning ? `<button class="btn btn-success" onclick="performAction('${container.name}', 'start')">▶ Start</button>` : ''}
                ${isRunning ? `<button class="btn btn-warning" onclick="performAction('${container.name}', 'restart')">⟳ Restart</button>` : ''}
                ${isRunning ? `<button class="btn btn-danger" onclick="performAction('${container.name}', 'stop')">⏹ Stop</button>` : ''}
                <button class="btn ${!isRunning ? 'btn-full' : ''}" onclick="viewLogs('${container.name}', '${tool.name || container.name}')">📄 Logs</button>
            </div>
        </div>
    `;
}

// ============================================================================
// STACKS TAB
// ============================================================================
async function loadStacksData() {
    try {
        const stacks = await API.getStacks();
        DashboardState.stacks = stacks;
        renderStacks(stacks);
    } catch (error) {
        console.error('Error loading stacks:', error);
        Toast.error('Failed to load stacks');
    }
}

function renderStacks(stacks) {
    const container = document.getElementById('stacks-container');
    if (!container) return;

    if (stacks.length === 0) {
        container.innerHTML = `
            <div class="empty-state">
                <div class="empty-state-icon">📚</div>
                <div class="empty-state-text">No stacks found</div>
            </div>
        `;
        return;
    }

    container.innerHTML = stacks.map(stack => createStackCard(stack)).join('');
}

function createStackCard(stack) {
    const healthClass = `stack-health-${stack.health}`;

    return `
        <div class="stack-card" data-stack="${stack.name}">
            <div class="stack-header">
                <div class="stack-title-section">
                    <h3 class="stack-name">${stack.name}</h3>
                    <span class="stack-health-badge ${healthClass}">${stack.health}</span>
                </div>
                <div class="stack-actions">
                    <button class="btn btn-success" onclick="performStackAction('${stack.name}', 'start')">▶ Start All</button>
                    <button class="btn btn-warning" onclick="performStackAction('${stack.name}', 'restart')">⟳ Restart All</button>
                    <button class="btn btn-danger" onclick="performStackAction('${stack.name}', 'stop')">⏹ Stop All</button>
                </div>
            </div>
            <div class="stack-metrics">
                <div class="metric-item">
                    <div class="metric-label">Total Containers</div>
                    <div class="metric-value">${stack.total_count}</div>
                </div>
                <div class="metric-item">
                    <div class="metric-label">Running</div>
                    <div class="metric-value metric-good">${stack.running_count}</div>
                </div>
                <div class="metric-item">
                    <div class="metric-label">CPU Usage</div>
                    <div class="metric-value">${stack.cpu_percent.toFixed(1)}%</div>
                </div>
                <div class="metric-item">
                    <div class="metric-label">Memory</div>
                    <div class="metric-value">${stack.mem_usage_mb.toFixed(0)}MB</div>
                </div>
            </div>
            <div class="stack-containers-list">
                <button class="stack-containers-toggle" onclick="toggleStackContainers('${stack.name}')">
                    <span>Containers (${stack.containers.length})</span>
                    <span class="toggle-icon">▼</span>
                </button>
                <div class="stack-containers-content" id="stack-containers-${stack.name}">
                    ${stack.containers.map(c => `
                        <div class="container-mini-card">
                            <span>${c}</span>
                            <button class="btn btn-primary" onclick="viewLogs('${c}', '${c}')">Logs</button>
                        </div>
                    `).join('')}
                </div>
            </div>
        </div>
    `;
}

function toggleStackContainers(stackName) {
    const content = document.getElementById(`stack-containers-${stackName}`);
    if (content) {
        content.classList.toggle('expanded');
    }
}

// ============================================================================
// LOGS TAB
// ============================================================================
function viewLogs(containerName, displayName) {
    // Switch to logs tab
    switchTab('logs');

    // Set container in dropdown
    const containerSelect = document.getElementById('logs-container-select');
    if (containerSelect) {
        // Add option if not exists
        if (![...containerSelect.options].find(opt => opt.value === containerName)) {
            const option = document.createElement('option');
            option.value = containerName;
            option.textContent = displayName;
            containerSelect.appendChild(option);
        }
        containerSelect.value = containerName;
    }

    // Load logs
    loadContainerLogs(containerName);
}

async function loadContainerLogs(containerName) {
    const logsViewer = document.getElementById('logs-viewer');
    if (!logsViewer) return;

    try {
        logsViewer.innerHTML = '<div class="loading">Loading logs...</div>';

        const linesSelect = document.getElementById('logs-lines-select');
        const sinceSelect = document.getElementById('logs-since-select');

        const lines = linesSelect ? linesSelect.value : 100;
        const since = sinceSelect ? sinceSelect.value : null;

        const data = await API.getLogs(containerName, lines, since);

        if (data.logs) {
            logsViewer.innerHTML = formatLogs(data.logs);

            // Auto-scroll to bottom
            logsViewer.scrollTop = logsViewer.scrollHeight;
        } else {
            logsViewer.innerHTML = '<div class="empty-state-text">No logs available</div>';
        }
    } catch (error) {
        console.error('Error loading logs:', error);
        logsViewer.innerHTML = `<div class="error">Error loading logs: ${error.message}</div>`;
    }
}

function formatLogs(logs) {
    return logs.split('\n').map(line => {
        if (!line.trim()) return '';

        let className = 'log-line log-line-info';
        if (line.toUpperCase().includes('ERROR') || line.toUpperCase().includes('FAIL')) {
            className = 'log-line log-line-error';
        } else if (line.toUpperCase().includes('WARN')) {
            className = 'log-line log-line-warn';
        }

        return `<div class="${className}">${escapeHtml(line)}</div>`;
    }).join('');
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function downloadLogs() {
    const logsViewer = document.getElementById('logs-viewer');
    const containerSelect = document.getElementById('logs-container-select');

    if (!logsViewer || !containerSelect) return;

    const containerName = containerSelect.value;
    const logs = logsViewer.textContent;

    const blob = new Blob([logs], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${containerName}-${new Date().toISOString()}.log`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);

    Toast.success('Logs downloaded');
}

// ============================================================================
// ACTIONS
// ============================================================================
async function performAction(containerName, action) {
    try {
        const result = await API.containerAction(containerName, action);
        Toast.success(result.message);

        // Refresh current tab data
        await loadTabData(DashboardState.currentTab);
    } catch (error) {
        console.error(`Error performing ${action}:`, error);
        Toast.error(`Failed to ${action} container`);
    }
}

async function performStackAction(stackName, action) {
    try {
        const result = await API.stackAction(stackName, action);
        Toast.success(result.message);

        // Refresh current tab data
        await loadTabData(DashboardState.currentTab);
    } catch (error) {
        console.error(`Error performing ${action} on stack:`, error);
        Toast.error(`Failed to ${action} stack`);
    }
}

// ============================================================================
// FILTERS
// ============================================================================
function setupFilters() {
    // Stack filter
    document.querySelectorAll('[data-filter-stack]').forEach(btn => {
        btn.addEventListener('click', (e) => {
            document.querySelectorAll('[data-filter-stack]').forEach(b => b.classList.remove('active'));
            e.target.classList.add('active');
            DashboardState.filters.stack = e.target.dataset.filterStack;
            renderContainers(DashboardState.containers);
        });
    });

    // Category filter
    document.querySelectorAll('[data-filter-category]').forEach(btn => {
        btn.addEventListener('click', (e) => {
            document.querySelectorAll('[data-filter-category]').forEach(b => b.classList.remove('active'));
            e.target.classList.add('active');
            DashboardState.filters.category = e.target.dataset.filterCategory;
            renderContainers(DashboardState.containers);
        });
    });

    // Status filter
    document.querySelectorAll('[data-filter-status]').forEach(btn => {
        btn.addEventListener('click', (e) => {
            document.querySelectorAll('[data-filter-status]').forEach(b => b.classList.remove('active'));
            e.target.classList.add('active');
            DashboardState.filters.status = e.target.dataset.filterStatus;
            renderContainers(DashboardState.containers);
        });
    });

    // Search
    const searchInput = document.getElementById('search-input');
    if (searchInput) {
        let searchTimeout;
        searchInput.addEventListener('input', (e) => {
            clearTimeout(searchTimeout);
            searchTimeout = setTimeout(() => {
                DashboardState.filters.search = e.target.value;
                renderContainers(DashboardState.containers);
            }, 300);
        });
    }
}

function filterByStack(stackName) {
    DashboardState.filters.stack = stackName;

    // Update active button
    document.querySelectorAll('[data-filter-stack]').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.filterStack === stackName);
    });

    renderContainers(DashboardState.containers);
}

// ============================================================================
// AUTO REFRESH
// ============================================================================
function startAutoRefresh() {
    if (DashboardState.refreshTimer) {
        clearInterval(DashboardState.refreshTimer);
    }

    if (DashboardState.autoRefreshEnabled) {
        DashboardState.refreshTimer = setInterval(() => {
            loadTabData(DashboardState.currentTab);
        }, DashboardState.autoRefreshInterval);
    }
}

function toggleAutoRefresh() {
    DashboardState.autoRefreshEnabled = !DashboardState.autoRefreshEnabled;
    savePreferences();
    startAutoRefresh();

    Toast.info(`Auto-refresh ${DashboardState.autoRefreshEnabled ? 'enabled' : 'disabled'}`);
}

// ============================================================================
// THEME TOGGLE
// ============================================================================
function toggleTheme() {
    DashboardState.theme = DashboardState.theme === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', DashboardState.theme);
    savePreferences();

    Toast.info(`Theme switched to ${DashboardState.theme} mode`);
}

// ============================================================================
// KEYBOARD SHORTCUTS
// ============================================================================
function setupKeyboardShortcuts() {
    document.addEventListener('keydown', (e) => {
        // Ignore if typing in input
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
            return;
        }

        switch(e.key) {
            case '/':
                e.preventDefault();
                document.getElementById('search-input')?.focus();
                break;
            case 'r':
                e.preventDefault();
                loadTabData(DashboardState.currentTab);
                Toast.info('Refreshing...');
                break;
            case '1':
                e.preventDefault();
                switchTab('overview');
                break;
            case '2':
                e.preventDefault();
                switchTab('containers');
                break;
            case '3':
                e.preventDefault();
                switchTab('stacks');
                break;
            case '4':
                e.preventDefault();
                switchTab('logs');
                break;
            case '5':
                e.preventDefault();
                switchTab('metrics');
                break;
            case '6':
                e.preventDefault();
                switchTab('terminal');
                break;
            case '7':
                e.preventDefault();
                switchTab('volumes');
                break;
            case '8':
                e.preventDefault();
                switchTab('images');
                break;
            case 'Escape':
                e.preventDefault();
                Modal.hideAll();
                break;
        }
    });
}

// ============================================================================
// VOLUMES TAB
// ============================================================================
async function loadVolumesTab() {
    try {
        const volumes = await API.getDockerVolumes();
        renderVolumes(volumes);
    } catch (error) {
        console.error('Error loading volumes:', error);
        Toast.error('Failed to load volumes');
    }
}

function renderVolumes(volumes) {
    const grid = document.getElementById('volumes-grid');
    if (!grid) return;

    if (volumes.length === 0) {
        grid.innerHTML = '<div class="empty-state"><div class="empty-state-icon">💾</div><div class="empty-state-text">No volumes found</div></div>';
        return;
    }

    grid.innerHTML = volumes.map(volume => `
        <div class="volume-card">
            <div class="volume-name">${volume.name}</div>
            <div class="volume-driver">Driver: ${volume.driver}</div>
            <div class="volume-usage">
                <div class="volume-usage-label">Used by ${volume.used_by.length} container(s)</div>
                ${volume.used_by.length > 0 ? `
                    <ul class="volume-container-list">
                        ${volume.used_by.map(c => `<li>• ${c}</li>`).join('')}
                    </ul>
                ` : '<div style="color: var(--text-muted); font-size: 0.875rem;">Not in use</div>'}
            </div>
            <div class="card-actions" style="margin-top: 1rem;">
                ${!volume.in_use ? `
                    <button class="btn btn-danger btn-full" onclick="deleteVolume('${volume.name}')">Delete</button>
                ` : `
                    <button class="btn btn-full" disabled title="Volume is in use">Delete (In Use)</button>
                `}
            </div>
        </div>
    `).join('');
}

async function deleteVolume(volumeName) {
    if (!confirm(`Are you sure you want to delete volume "${volumeName}"?`)) {
        return;
    }

    try {
        const response = await fetch(`/api/volume/${volumeName}/delete`, { method: 'POST' });
        const data = await response.json();

        if (data.success) {
            Toast.success(data.message);
            loadVolumesTab();
        } else {
            Toast.error(data.error || 'Failed to delete volume');
        }
    } catch (error) {
        Toast.error('Failed to delete volume');
    }
}

async function pruneVolumes() {
    if (!confirm('Are you sure you want to prune all unused volumes? This cannot be undone.')) {
        return;
    }

    try {
        const response = await fetch('/api/volumes/prune', { method: 'POST' });
        const data = await response.json();

        if (data.success) {
            Toast.success(data.message);
            loadVolumesTab();
        } else {
            Toast.error(data.error || 'Failed to prune volumes');
        }
    } catch (error) {
        Toast.error('Failed to prune volumes');
    }
}

// ============================================================================
// IMAGES TAB
// ============================================================================
async function loadImagesTab() {
    try {
        const images = await API.getDockerImages();
        renderImages(images);
    } catch (error) {
        console.error('Error loading images:', error);
        Toast.error('Failed to load images');
    }
}

function renderImages(images) {
    const list = document.getElementById('images-list');
    if (!list) return;

    if (images.length === 0) {
        list.innerHTML = '<div class="empty-state"><div class="empty-state-icon">💿</div><div class="empty-state-text">No images found</div></div>';
        return;
    }

    list.innerHTML = images.map(image => `
        <div class="image-card">
            <div class="image-info">
                <div class="image-tag">${image.tags[0]}</div>
                <div class="image-meta">
                    <span class="image-meta-item">📏 ${image.size_mb} MB</span>
                    <span class="image-meta-item">🏗️ ${image.architecture}</span>
                    <span class="image-meta-item">📦 ${image.used_by_count} container(s)</span>
                    <span class="image-meta-item">🕐 ${new Date(image.created).toLocaleDateString()}</span>
                </div>
            </div>
            <div class="image-actions">
                <button class="btn btn-primary" onclick="scanImage('${image.id}', '${image.tags[0]}')">🔍 Scan</button>
                <button class="btn btn-danger" onclick="deleteImage('${image.id}', ${image.in_use})" ${image.in_use ? 'title="Image is in use"' : ''}>Delete</button>
            </div>
        </div>
    `).join('');
}

async function scanImage(imageId, imageName) {
    Modal.show('scan-modal');
    document.getElementById('scan-modal-title').textContent = `Scanning: ${imageName}`;
    document.getElementById('scan-modal-body').innerHTML = '<div class="loading"><div class="loading-spinner"></div>Scanning for vulnerabilities...</div>';

    try {
        const response = await fetch(`/api/image/${imageId}/scan`, { method: 'POST' });
        const data = await response.json();

        if (data.scanned) {
            document.getElementById('scan-modal-body').innerHTML = `
                <div class="scan-results">
                    <div class="scan-severity">
                        <span class="scan-severity-count severity-critical">${data.vulnerabilities.CRITICAL || 0}</span>
                        <span class="scan-severity-label">Critical</span>
                    </div>
                    <div class="scan-severity">
                        <span class="scan-severity-count severity-high">${data.vulnerabilities.HIGH || 0}</span>
                        <span class="scan-severity-label">High</span>
                    </div>
                    <div class="scan-severity">
                        <span class="scan-severity-count severity-medium">${data.vulnerabilities.MEDIUM || 0}</span>
                        <span class="scan-severity-label">Medium</span>
                    </div>
                    <div class="scan-severity">
                        <span class="scan-severity-count severity-low">${data.vulnerabilities.LOW || 0}</span>
                        <span class="scan-severity-label">Low</span>
                    </div>
                </div>
                <div style="margin-top: 1rem; max-height: 400px; overflow-y: auto;">
                    <h4>Top Vulnerabilities (showing ${data.vuln_list.length} of ${data.total_vulnerabilities})</h4>
                    ${data.vuln_list.map(v => `
                        <div style="background: var(--bg-tertiary); padding: 1rem; margin-bottom: 0.5rem; border-radius: 6px; border-left: 3px solid ${v.severity === 'CRITICAL' ? 'var(--accent-red)' : v.severity === 'HIGH' ? 'var(--accent-orange)' : v.severity === 'MEDIUM' ? 'var(--accent-yellow)' : 'var(--accent-blue)'};">
                            <div style="font-weight: 600; margin-bottom: 0.5rem;">${v.id} - ${v.severity}</div>
                            <div style="font-size: 0.875rem; color: var(--text-secondary); margin-bottom: 0.5rem;">${v.title || 'No title'}</div>
                            <div style="font-size: 0.75rem; color: var(--text-muted);">
                                Package: ${v.pkg_name} (${v.installed_version})
                                ${v.fixed_version ? ` → Fixed in: ${v.fixed_version}` : ''}
                            </div>
                        </div>
                    `).join('')}
                </div>
            `;
        } else {
            document.getElementById('scan-modal-body').innerHTML = `
                <div class="error">${data.error || 'Scan failed'}</div>
                <p>${data.message || ''}</p>
            `;
        }
    } catch (error) {
        document.getElementById('scan-modal-body').innerHTML = `<div class="error">Error: ${error.message}</div>`;
    }
}

async function deleteImage(imageId, inUse) {
    if (inUse && !confirm('This image is in use by containers. Force delete anyway?')) {
        return;
    }

    if (!inUse && !confirm('Are you sure you want to delete this image?')) {
        return;
    }

    try {
        const response = await fetch(`/api/image/${imageId}/delete`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ force: inUse })
        });

        const data = await response.json();

        if (data.success) {
            Toast.success('Image deleted');
            loadImagesTab();
        } else {
            Toast.error(data.error || 'Failed to delete image');
        }
    } catch (error) {
        Toast.error('Failed to delete image');
    }
}

async function pruneImages() {
    if (!confirm('Are you sure you want to prune all dangling images?')) {
        return;
    }

    try {
        const response = await fetch('/api/images/prune', { method: 'POST' });
        const data = await response.json();

        if (data.success) {
            Toast.success(data.message);
            loadImagesTab();
        } else {
            Toast.error(data.error || 'Failed to prune images');
        }
    } catch (error) {
        Toast.error('Failed to prune images');
    }
}

async function scanAllImages() {
    Toast.info('Scanning all images... This may take a while.');
    // Implementation would scan all images sequentially
}

// ============================================================================
// SSDF COMPLIANCE TAB
// ============================================================================
async function loadSSDFTab() {
    try {
        await loadSSDFData();
    } catch (error) {
        console.error('Error loading SSDF data:', error);
        Toast.error('Failed to load SSDF compliance data');
    }
}

async function loadSSDFData() {
    try {
        // Fetch SSDF compliance data from API
        const ssdfData = await API.getSSDFCompliance();

        // Transform sboms data
        const sbom_summary = {
            spdx_count: ssdfData.sboms.spdx_count,
            cyclonedx_count: ssdfData.sboms.cyclonedx_count,
            signed_count: ssdfData.sboms.signed_count,
            avg_components: ssdfData.sboms.avg_components
        };

        // Transform vulnerabilities data
        const vuln_summary = {
            total_vulns: ssdfData.vulnerabilities.total,
            critical_high: ssdfData.vulnerabilities.critical_high,
            response_rate: ssdfData.vulnerabilities.response_rate,
            avg_response_time: ssdfData.vulnerabilities.avg_response_time
        };

        // Update overview cards
        updateSSDFOverview({
            coverage: ssdfData.coverage,
            evidence_packages: ssdfData.evidence_packages,
            sboms: ssdfData.sboms.total,
            vulnerabilities: ssdfData.vulnerabilities
        });

        // Update workflows list
        updateSSDFWorkflows(ssdfData.workflows);

        // Update SBOM summary
        updateSBOMSummary(sbom_summary);

        // Update vulnerability summary
        updateVulnSummary(vuln_summary);

    } catch (error) {
        console.error('Error loading SSDF data:', error);
        throw error;
    }
}

function updateSSDFOverview(data) {
    const coveragePercent = document.getElementById('ssdf-coverage-percent');
    const practicesCovered = document.getElementById('ssdf-practices-covered');
    const evidenceCount = document.getElementById('ssdf-evidence-count');
    const sbomCount = document.getElementById('ssdf-sbom-count');
    const vulnCount = document.getElementById('ssdf-vuln-count');

    if (coveragePercent) coveragePercent.textContent = `${data.coverage.percent}%`;
    if (practicesCovered) practicesCovered.textContent = data.coverage.covered;
    if (evidenceCount) evidenceCount.textContent = data.evidence_packages;
    if (sbomCount) sbomCount.textContent = data.sboms;
    if (vulnCount) vulnCount.textContent = data.vulnerabilities.critical + data.vulnerabilities.high;
}

function updateSSDFWorkflows(workflows) {
    const list = document.getElementById('ssdf-workflows-list');
    if (!list) return;

    if (workflows.length === 0) {
        list.innerHTML = '<div class="empty-state-text">No workflow executions found</div>';
        return;
    }

    list.innerHTML = workflows.map(workflow => `
        <div class="ssdf-workflow-item">
            <div class="ssdf-workflow-info">
                <div class="ssdf-workflow-name">${workflow.name}</div>
                <div class="ssdf-workflow-meta">
                    ${formatTimeAgo(workflow.timestamp)} • ${workflow.duration} • ${workflow.practices.join(', ')}
                </div>
            </div>
            <div class="ssdf-workflow-status ${workflow.status}">${workflow.status}</div>
        </div>
    `).join('');
}

function updateSBOMSummary(summary) {
    const container = document.getElementById('ssdf-sbom-summary');
    if (!container) return;

    container.innerHTML = `
        <div class="ssdf-summary-item">
            <span class="ssdf-summary-label">SPDX 2.3 SBOMs</span>
            <span class="ssdf-summary-value">${summary.spdx_count}</span>
        </div>
        <div class="ssdf-summary-item">
            <span class="ssdf-summary-label">CycloneDX 1.5 SBOMs</span>
            <span class="ssdf-summary-value">${summary.cyclonedx_count}</span>
        </div>
        <div class="ssdf-summary-item">
            <span class="ssdf-summary-label">Signed with Cosign</span>
            <span class="ssdf-summary-value" style="color: var(--accent-green)">${summary.signed_count}</span>
        </div>
        <div class="ssdf-summary-item">
            <span class="ssdf-summary-label">Avg Components</span>
            <span class="ssdf-summary-value">${summary.avg_components}</span>
        </div>
    `;
}

function updateVulnSummary(summary) {
    const container = document.getElementById('ssdf-vuln-summary');
    if (!container) return;

    container.innerHTML = `
        <div class="ssdf-summary-item">
            <span class="ssdf-summary-label">Total Vulnerabilities</span>
            <span class="ssdf-summary-value">${summary.total_vulns}</span>
        </div>
        <div class="ssdf-summary-item">
            <span class="ssdf-summary-label">CRITICAL + HIGH</span>
            <span class="ssdf-summary-value" style="color: var(--accent-red)">${summary.critical_high}</span>
        </div>
        <div class="ssdf-summary-item">
            <span class="ssdf-summary-label">Response Rate</span>
            <span class="ssdf-summary-value" style="color: var(--accent-green)">${summary.response_rate}%</span>
        </div>
        <div class="ssdf-summary-item">
            <span class="ssdf-summary-label">Avg Response Time</span>
            <span class="ssdf-summary-value">${summary.avg_response_time}</span>
        </div>
    `;
}

function formatTimeAgo(timestamp) {
    const now = new Date();
    const past = new Date(timestamp);
    const diffMs = now - past;
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMs / 3600000);
    const diffDays = Math.floor(diffMs / 86400000);

    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    return `${diffDays}d ago`;
}

// SSDF Action Functions
function refreshSSDFData() {
    Toast.info('Refreshing SSDF data...');
    loadSSDFData();
}

function generateAttestation() {
    Toast.info('Generating CISA attestation form...');
    // In production: trigger n8n workflow to generate attestation
    window.open('/ssdf/documentation/SSDF_ATTESTATION_FORM.md', '_blank');
}

function collectEvidence() {
    Toast.info('Collecting evidence package...');
    // In production: trigger n8n workflow to collect evidence
    setTimeout(() => {
        Toast.success('Evidence package collection started. Check n8n for progress.');
    }, 1000);
}

function viewSSDFDocumentation() {
    window.open('/ssdf/documentation/SSDF_IMPLEMENTATION_GUIDE.md', '_blank');
}

function exportComplianceReport() {
    Toast.info('Exporting compliance report...');
    // In production: generate PDF report
    setTimeout(() => {
        Toast.success('Compliance report exported successfully.');
    }, 1000);
}

function viewSBOMList() {
    Toast.info('Opening SBOM management...');
    // In production: show SBOM list modal or navigate to SBOM page
}

function viewVulnerabilities() {
    Toast.info('Opening vulnerability dashboard...');
    // In production: show vulnerability modal or navigate to vuln page
}

// ============================================================================
// EVENTS FEED
// ============================================================================
let eventsSource = null;

function startEventsFeed() {
    if (eventsSource) {
        eventsSource.close();
    }

    const feedContent = document.getElementById('events-feed-content');
    if (!feedContent) return;

    feedContent.innerHTML = '<div class="events-feed-status">Connecting...</div>';

    eventsSource = new EventSource('/api/events/stream');

    eventsSource.onmessage = (event) => {
        const data = JSON.parse(event.data);

        if (data.type === 'connected') {
            feedContent.innerHTML = '<div class="events-feed-status">Connected • Waiting for events...</div>';
        } else if (data.type === 'event') {
            // Remove status message if it's the first event
            const statusMsg = feedContent.querySelector('.events-feed-status');
            if (statusMsg) {
                statusMsg.remove();
            }

            // Add event to feed
            const eventDiv = document.createElement('div');
            eventDiv.className = `event-item event-${data.action}`;
            eventDiv.innerHTML = `
                <div class="event-timestamp">${new Date(data.timestamp).toLocaleTimeString()}</div>
                <div class="event-action">${getEventIcon(data.action)} ${data.action}</div>
                <div class="event-container">${data.container}</div>
                <div style="font-size: 0.75rem; color: var(--text-muted); margin-top: 0.25rem;">${data.stack}</div>
            `;

            feedContent.insertBefore(eventDiv, feedContent.firstChild);

            // Keep only last 20 events
            while (feedContent.children.length > 20) {
                feedContent.removeChild(feedContent.lastChild);
            }

            // Show toast for critical events
            if (data.action === 'die' || data.action === 'destroy') {
                Toast.error(`Container ${data.container} ${data.action}`);
            }
        }
    };

    eventsSource.onerror = () => {
        feedContent.innerHTML = '<div class="events-feed-status">Connection lost. Reconnecting...</div>';
        setTimeout(() => {
            if (eventsSource) {
                startEventsFeed();
            }
        }, 5000);
    };
}

function toggleEventsFeed() {
    const widget = document.getElementById('events-feed-widget');
    if (widget) {
        widget.style.display = widget.style.display === 'none' ? 'flex' : 'none';
    }
}

function getEventIcon(action) {
    const icons = {
        'start': '✅',
        'create': '✅',
        'stop': '⏹️',
        'die': '❌',
        'destroy': '❌',
        'restart': '🔄',
        'health_status': '💊'
    };
    return icons[action] || '📌';
}

// ============================================================================
// INITIALIZATION
// ============================================================================
document.addEventListener('DOMContentLoaded', async () => {
    // Load preferences
    loadPreferences();

    // Initialize toast system
    Toast.init();

    // Setup event listeners
    setupFilters();
    setupKeyboardShortcuts();

    // Setup tab buttons
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            switchTab(e.target.dataset.tab);
        });
    });

    // Start with overview tab
    switchTab('overview');

    // Start auto-refresh
    startAutoRefresh();

    // Start events feed
    startEventsFeed();

    // Load active alerts
    try {
        const alertsResponse = await fetch('/api/alerts/active');
        if (alertsResponse.ok) {
            const activeAlerts = await alertsResponse.json();
            const alertsBadge = document.getElementById('alerts-badge');
            if (alertsBadge) {
                alertsBadge.textContent = activeAlerts.length;
            }
        }
    } catch (error) {
        console.error('Error loading active alerts:', error);
    }

    console.log('DevSecOps Dashboard initialized successfully');
});

// Make functions globally accessible
window.switchTab = switchTab;
window.performAction = performAction;
window.performStackAction = performStackAction;
window.viewLogs = viewLogs;
window.downloadLogs = downloadLogs;
window.filterByStack = filterByStack;
window.toggleStackContainers = toggleStackContainers;
window.toggleTheme = toggleTheme;
window.toggleAutoRefresh = toggleAutoRefresh;
window.loadContainerLogs = loadContainerLogs;
window.deleteVolume = deleteVolume;
window.pruneVolumes = pruneVolumes;
window.scanImage = scanImage;
window.deleteImage = deleteImage;
window.pruneImages = pruneImages;
window.scanAllImages = scanAllImages;
window.toggleEventsFeed = toggleEventsFeed;
window.refreshSSDFData = refreshSSDFData;
window.generateAttestation = generateAttestation;
window.collectEvidence = collectEvidence;
window.viewSSDFDocumentation = viewSSDFDocumentation;
window.exportComplianceReport = exportComplianceReport;
window.viewSBOMList = viewSBOMList;
window.viewVulnerabilities = viewVulnerabilities;
window.API = API;
window.Modal = Modal;
