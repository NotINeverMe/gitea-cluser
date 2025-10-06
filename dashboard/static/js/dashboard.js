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
        const response = await fetch('/api/docker/images');
        if (!response.ok) throw new Error('Failed to fetch images');
        return await response.json();
    },

    async getDockerVolumes() {
        const response = await fetch('/api/docker/volumes');
        if (!response.ok) throw new Error('Failed to fetch volumes');
        return await response.json();
    },

    async getDockerNetworks() {
        const response = await fetch('/api/docker/networks');
        if (!response.ok) throw new Error('Failed to fetch networks');
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
            case 'Escape':
                e.preventDefault();
                Modal.hideAll();
                break;
        }
    });
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
