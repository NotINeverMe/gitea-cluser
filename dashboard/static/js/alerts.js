/**
 * DevSecOps Dashboard - Alerts Module
 * Alert rules management and notification system
 */

// ============================================================================
// ALERTS FUNCTIONS
// ============================================================================
async function loadAlertRules() {
    try {
        const response = await fetch('/api/alerts/rules');
        const rules = await response.json();

        renderAlertRules(rules);
    } catch (error) {
        console.error('Error loading alert rules:', error);
        Toast.error('Failed to load alert rules');
    }
}

function renderAlertRules(rules) {
    const container = document.getElementById('alerts-config-body');
    if (!container) return;

    if (rules.length === 0) {
        container.innerHTML = '<div class="empty-state-text">No alert rules configured</div>';
        return;
    }

    container.innerHTML = rules.map(rule => `
        <div class="alert-rule-card" style="background: var(--bg-tertiary); padding: 1rem; border-radius: 8px; margin-bottom: 1rem; border: 1px solid var(--border-color);">
            <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                <div style="flex: 1;">
                    <h4 style="margin: 0 0 0.5rem 0; color: var(--text-primary);">${rule.name}</h4>
                    <div style="font-size: 0.875rem; color: var(--text-secondary); margin-bottom: 0.5rem;">
                        <strong>Type:</strong> ${rule.type}
                    </div>
                    ${rule.threshold ? `
                        <div style="font-size: 0.875rem; color: var(--text-secondary); margin-bottom: 0.5rem;">
                            <strong>Threshold:</strong> ${rule.threshold}${rule.type.includes('cpu') || rule.type.includes('memory') ? '%' : ''}
                        </div>
                    ` : ''}
                    ${rule.duration ? `
                        <div style="font-size: 0.875rem; color: var(--text-secondary); margin-bottom: 0.5rem;">
                            <strong>Duration:</strong> ${rule.duration}s
                        </div>
                    ` : ''}
                    <div style="font-size: 0.875rem; color: var(--text-secondary);">
                        <strong>Google Chat:</strong> ${rule.notify_google_chat ? 'Enabled' : 'Disabled'}
                    </div>
                </div>
                <div style="display: flex; gap: 0.5rem;">
                    <label class="toggle-switch" style="position: relative; display: inline-block; width: 50px; height: 24px;">
                        <input type="checkbox" ${rule.enabled ? 'checked' : ''} onchange="toggleAlertRule('${rule.id}', this.checked)" style="opacity: 0; width: 0; height: 0;">
                        <span style="position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0; background-color: ${rule.enabled ? 'var(--accent-green)' : 'var(--border-color)'}; transition: 0.4s; border-radius: 24px;"></span>
                    </label>
                    <button class="btn btn-danger" onclick="deleteAlertRule('${rule.id}')" style="padding: 0.5rem;">Delete</button>
                </div>
            </div>
        </div>
    `).join('');
}

async function toggleAlertRule(ruleId, enabled) {
    try {
        // Implementation would update the rule
        Toast.info(`Alert rule ${enabled ? 'enabled' : 'disabled'}`);
    } catch (error) {
        console.error('Error toggling alert rule:', error);
        Toast.error('Failed to toggle alert rule');
    }
}

async function deleteAlertRule(ruleId) {
    if (!confirm('Are you sure you want to delete this alert rule?')) {
        return;
    }

    try {
        const response = await fetch(`/api/alerts/rules/${ruleId}`, {
            method: 'DELETE'
        });

        if (response.ok) {
            Toast.success('Alert rule deleted');
            loadAlertRules();
        } else {
            Toast.error('Failed to delete alert rule');
        }
    } catch (error) {
        console.error('Error deleting alert rule:', error);
        Toast.error('Failed to delete alert rule');
    }
}

function addAlertRule() {
    // This would show a form to create a new alert rule
    Toast.info('Add alert rule functionality - Coming soon!');
}

async function loadActiveAlerts() {
    try {
        const response = await fetch('/api/alerts/active');
        const alerts = await response.json();

        // Update badge count
        const badge = document.getElementById('alerts-badge');
        if (badge) {
            badge.textContent = alerts.length;
            badge.style.display = alerts.length > 0 ? 'flex' : 'none';
        }

        return alerts;
    } catch (error) {
        console.error('Error loading active alerts:', error);
        return [];
    }
}

// Poll for active alerts every 30 seconds
setInterval(loadActiveAlerts, 30000);

// Make functions globally accessible
window.loadAlertRules = loadAlertRules;
window.toggleAlertRule = toggleAlertRule;
window.deleteAlertRule = deleteAlertRule;
window.addAlertRule = addAlertRule;
window.loadActiveAlerts = loadActiveAlerts;
