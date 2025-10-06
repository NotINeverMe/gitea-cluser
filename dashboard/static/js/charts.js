/**
 * DevSecOps Dashboard - Charts Module
 * Chart.js integration for metrics visualization
 */

// ============================================================================
// CHART CONFIGURATION
// ============================================================================
const ChartConfig = {
    defaultOptions: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            legend: {
                display: true,
                position: 'top',
                labels: {
                    color: '#c9d1d9',
                    font: {
                        family: '-apple-system, BlinkMacSystemFont, "Segoe UI"',
                        size: 12
                    }
                }
            },
            tooltip: {
                backgroundColor: '#161b22',
                titleColor: '#c9d1d9',
                bodyColor: '#8b949e',
                borderColor: '#30363d',
                borderWidth: 1,
                padding: 12,
                displayColors: true,
                callbacks: {
                    label: function(context) {
                        let label = context.dataset.label || '';
                        if (label) {
                            label += ': ';
                        }
                        if (context.parsed.y !== null) {
                            label += context.parsed.y.toFixed(2);
                        }
                        return label;
                    }
                }
            }
        },
        scales: {
            x: {
                grid: {
                    color: '#21262d',
                    borderColor: '#30363d'
                },
                ticks: {
                    color: '#8b949e',
                    font: {
                        size: 11
                    }
                }
            },
            y: {
                grid: {
                    color: '#21262d',
                    borderColor: '#30363d'
                },
                ticks: {
                    color: '#8b949e',
                    font: {
                        size: 11
                    }
                }
            }
        }
    },

    colors: {
        blue: '#58a6ff',
        green: '#3fb950',
        yellow: '#d29922',
        red: '#f85149',
        purple: '#bc8cff',
        orange: '#ff9500',
        cyan: '#39c5cf'
    }
};

// ============================================================================
// CHART INSTANCES
// ============================================================================
const Charts = {
    cpuHistory: null,
    memoryHistory: null,
    networkHistory: null,
    containerTimeline: null,
    topCpuChart: null,
    topMemoryChart: null
};

// ============================================================================
// METRICS TAB - Time Series Charts
// ============================================================================
async function loadMetricsData() {
    try {
        // Load system metrics history
        const systemHistory = await API.getMetricsHistory(null, 1); // Last 1 hour

        // Create/update charts
        updateCpuHistoryChart(systemHistory.history);
        updateMemoryHistoryChart(systemHistory.history);

        // Load stack-specific charts if a stack is selected
        const stackSelect = document.getElementById('metrics-stack-select');
        if (stackSelect && stackSelect.value !== 'all') {
            await loadStackMetricsCharts(stackSelect.value);
        }

    } catch (error) {
        console.error('Error loading metrics data:', error);
        Toast.error('Failed to load metrics data');
    }
}

function updateCpuHistoryChart(history) {
    const ctx = document.getElementById('cpu-history-chart');
    if (!ctx) return;

    // Prepare data
    const labels = history.map(h => {
        const date = new Date(h[0]);
        return date.toLocaleTimeString();
    });
    const data = history.map(h => h[1]); // CPU percentage

    if (Charts.cpuHistory) {
        // Update existing chart
        Charts.cpuHistory.data.labels = labels;
        Charts.cpuHistory.data.datasets[0].data = data;
        Charts.cpuHistory.update();
    } else {
        // Create new chart
        Charts.cpuHistory = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [{
                    label: 'CPU Usage (%)',
                    data: data,
                    borderColor: ChartConfig.colors.blue,
                    backgroundColor: ChartConfig.colors.blue + '20',
                    borderWidth: 2,
                    fill: true,
                    tension: 0.4,
                    pointRadius: 0,
                    pointHoverRadius: 6
                }]
            },
            options: {
                ...ChartConfig.defaultOptions,
                plugins: {
                    ...ChartConfig.defaultOptions.plugins,
                    title: {
                        display: true,
                        text: 'CPU Usage Over Time',
                        color: '#c9d1d9',
                        font: { size: 16, weight: '600' }
                    }
                },
                scales: {
                    ...ChartConfig.defaultOptions.scales,
                    y: {
                        ...ChartConfig.defaultOptions.scales.y,
                        min: 0,
                        max: 100,
                        ticks: {
                            ...ChartConfig.defaultOptions.scales.y.ticks,
                            callback: function(value) {
                                return value + '%';
                            }
                        }
                    }
                }
            }
        });
    }
}

function updateMemoryHistoryChart(history) {
    const ctx = document.getElementById('memory-history-chart');
    if (!ctx) return;

    // Prepare data
    const labels = history.map(h => {
        const date = new Date(h[0]);
        return date.toLocaleTimeString();
    });
    const data = history.map(h => h[2]); // Memory percentage

    if (Charts.memoryHistory) {
        // Update existing chart
        Charts.memoryHistory.data.labels = labels;
        Charts.memoryHistory.data.datasets[0].data = data;
        Charts.memoryHistory.update();
    } else {
        // Create new chart
        Charts.memoryHistory = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [{
                    label: 'Memory Usage (%)',
                    data: data,
                    borderColor: ChartConfig.colors.purple,
                    backgroundColor: ChartConfig.colors.purple + '20',
                    borderWidth: 2,
                    fill: true,
                    tension: 0.4,
                    pointRadius: 0,
                    pointHoverRadius: 6
                }]
            },
            options: {
                ...ChartConfig.defaultOptions,
                plugins: {
                    ...ChartConfig.defaultOptions.plugins,
                    title: {
                        display: true,
                        text: 'Memory Usage Over Time',
                        color: '#c9d1d9',
                        font: { size: 16, weight: '600' }
                    }
                },
                scales: {
                    ...ChartConfig.defaultOptions.scales,
                    y: {
                        ...ChartConfig.defaultOptions.scales.y,
                        min: 0,
                        max: 100,
                        ticks: {
                            ...ChartConfig.defaultOptions.scales.y.ticks,
                            callback: function(value) {
                                return value + '%';
                            }
                        }
                    }
                }
            }
        });
    }
}

async function loadStackMetricsCharts(stackName) {
    try {
        const duration = document.getElementById('metrics-duration-select')?.value || 1;
        const data = await API.getStackMetricsHistory(stackName, duration);

        updateStackCpuChart(data.history, stackName);
        updateStackMemoryChart(data.history, stackName);

    } catch (error) {
        console.error('Error loading stack metrics:', error);
    }
}

function updateStackCpuChart(history, stackName) {
    const ctx = document.getElementById('stack-cpu-chart');
    if (!ctx) return;

    const labels = history.map(h => {
        const date = new Date(h[0]);
        return date.toLocaleTimeString();
    });
    const data = history.map(h => h[1]); // CPU

    const chart = Chart.getChart(ctx);
    if (chart) chart.destroy();

    new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: `${stackName} - CPU Usage (%)`,
                data: data,
                borderColor: ChartConfig.colors.green,
                backgroundColor: ChartConfig.colors.green + '20',
                borderWidth: 2,
                fill: true,
                tension: 0.4
            }]
        },
        options: ChartConfig.defaultOptions
    });
}

function updateStackMemoryChart(history, stackName) {
    const ctx = document.getElementById('stack-memory-chart');
    if (!ctx) return;

    const labels = history.map(h => {
        const date = new Date(h[0]);
        return date.toLocaleTimeString();
    });
    const data = history.map(h => h[2]); // Memory

    const chart = Chart.getChart(ctx);
    if (chart) chart.destroy();

    new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: `${stackName} - Memory Usage (%)`,
                data: data,
                borderColor: ChartConfig.colors.orange,
                backgroundColor: ChartConfig.colors.orange + '20',
                borderWidth: 2,
                fill: true,
                tension: 0.4
            }]
        },
        options: ChartConfig.defaultOptions
    });
}

// ============================================================================
// OVERVIEW TAB - Charts
// ============================================================================
function createTopConsumersCharts(data) {
    createTopCpuChart(data.top_cpu);
    createTopMemoryChart(data.top_memory);
}

function createTopCpuChart(topCpu) {
    const ctx = document.getElementById('top-cpu-chart');
    if (!ctx) return;

    if (Charts.topCpuChart) Charts.topCpuChart.destroy();

    const labels = topCpu.map(c => c.name);
    const data = topCpu.map(c => c.cpu_percent);

    Charts.topCpuChart = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: labels,
            datasets: [{
                label: 'CPU Usage (%)',
                data: data,
                backgroundColor: ChartConfig.colors.blue,
                borderColor: ChartConfig.colors.blue,
                borderWidth: 1
            }]
        },
        options: {
            ...ChartConfig.defaultOptions,
            indexAxis: 'y',
            plugins: {
                ...ChartConfig.defaultOptions.plugins,
                title: {
                    display: true,
                    text: 'Top 5 CPU Consumers',
                    color: '#c9d1d9',
                    font: { size: 14, weight: '600' }
                },
                legend: {
                    display: false
                }
            },
            scales: {
                x: {
                    ...ChartConfig.defaultOptions.scales.x,
                    ticks: {
                        ...ChartConfig.defaultOptions.scales.x.ticks,
                        callback: function(value) {
                            return value + '%';
                        }
                    }
                },
                y: {
                    ...ChartConfig.defaultOptions.scales.y
                }
            }
        }
    });
}

function createTopMemoryChart(topMemory) {
    const ctx = document.getElementById('top-memory-chart');
    if (!ctx) return;

    if (Charts.topMemoryChart) Charts.topMemoryChart.destroy();

    const labels = topMemory.map(c => c.name);
    const data = topMemory.map(c => c.mem_usage_mb);

    Charts.topMemoryChart = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: labels,
            datasets: [{
                label: 'Memory Usage (MB)',
                data: data,
                backgroundColor: ChartConfig.colors.purple,
                borderColor: ChartConfig.colors.purple,
                borderWidth: 1
            }]
        },
        options: {
            ...ChartConfig.defaultOptions,
            indexAxis: 'y',
            plugins: {
                ...ChartConfig.defaultOptions.plugins,
                title: {
                    display: true,
                    text: 'Top 5 Memory Consumers',
                    color: '#c9d1d9',
                    font: { size: 14, weight: '600' }
                },
                legend: {
                    display: false
                }
            },
            scales: {
                x: {
                    ...ChartConfig.defaultOptions.scales.x,
                    ticks: {
                        ...ChartConfig.defaultOptions.scales.x.ticks,
                        callback: function(value) {
                            return value + ' MB';
                        }
                    }
                },
                y: {
                    ...ChartConfig.defaultOptions.scales.y
                }
            }
        }
    });
}

// ============================================================================
// CONTAINER STATUS TIMELINE
// ============================================================================
function createContainerTimeline(history) {
    const ctx = document.getElementById('container-timeline-chart');
    if (!ctx) return;

    if (Charts.containerTimeline) Charts.containerTimeline.destroy();

    const labels = history.map(h => {
        const date = new Date(h[0]);
        return date.toLocaleTimeString();
    });
    const runningData = history.map(h => h[4]); // Running count

    Charts.containerTimeline = new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: 'Running Containers',
                data: runningData,
                borderColor: ChartConfig.colors.green,
                backgroundColor: ChartConfig.colors.green + '20',
                borderWidth: 2,
                fill: true,
                tension: 0.4,
                pointRadius: 3,
                pointHoverRadius: 6
            }]
        },
        options: {
            ...ChartConfig.defaultOptions,
            plugins: {
                ...ChartConfig.defaultOptions.plugins,
                title: {
                    display: true,
                    text: 'Container Status Timeline (Last 24h)',
                    color: '#c9d1d9',
                    font: { size: 14, weight: '600' }
                }
            },
            scales: {
                ...ChartConfig.defaultOptions.scales,
                y: {
                    ...ChartConfig.defaultOptions.scales.y,
                    beginAtZero: true,
                    ticks: {
                        ...ChartConfig.defaultOptions.scales.y.ticks,
                        stepSize: 1
                    }
                }
            }
        }
    });
}

// ============================================================================
// CHART UPDATE FUNCTIONS
// ============================================================================
function updateChartDuration(duration) {
    // Reload metrics with new duration
    loadMetricsData();
}

function updateChartStack(stackName) {
    if (stackName === 'all') {
        loadMetricsData();
    } else {
        loadStackMetricsCharts(stackName);
    }
}

// ============================================================================
// EXPORT FUNCTIONS
// ============================================================================
function exportChartAsImage(chartId) {
    const canvas = document.getElementById(chartId);
    if (!canvas) {
        Toast.error('Chart not found');
        return;
    }

    const url = canvas.toDataURL('image/png');
    const a = document.createElement('a');
    a.href = url;
    a.download = `${chartId}-${new Date().toISOString()}.png`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);

    Toast.success('Chart exported');
}

// ============================================================================
// INITIALIZATION
// ============================================================================
document.addEventListener('DOMContentLoaded', () => {
    // Setup duration selector
    const durationSelect = document.getElementById('metrics-duration-select');
    if (durationSelect) {
        durationSelect.addEventListener('change', (e) => {
            updateChartDuration(e.target.value);
        });
    }

    // Setup stack selector
    const stackSelect = document.getElementById('metrics-stack-select');
    if (stackSelect) {
        stackSelect.addEventListener('change', (e) => {
            updateChartStack(e.target.value);
        });
    }

    console.log('Charts module initialized');
});

// Make functions globally accessible
window.loadMetricsData = loadMetricsData;
window.createTopConsumersCharts = createTopConsumersCharts;
window.createContainerTimeline = createContainerTimeline;
window.exportChartAsImage = exportChartAsImage;
