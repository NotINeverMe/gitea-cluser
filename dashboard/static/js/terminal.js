/**
 * DevSecOps Dashboard - Terminal Module
 * Container terminal execution functionality
 */

// ============================================================================
// TERMINAL STATE
// ============================================================================
const TerminalState = {
    currentContainer: null,
    commandHistory: [],
    historyIndex: -1
};

// ============================================================================
// TERMINAL FUNCTIONS
// ============================================================================
async function loadTerminalTab() {
    try {
        // Populate container dropdown
        const containers = await API.getContainers();
        const runningContainers = containers.filter(c => c.status === 'running');

        const select = document.getElementById('terminal-container-select');
        if (select) {
            select.innerHTML = '<option value="">Select a container...</option>';
            runningContainers.forEach(c => {
                const option = document.createElement('option');
                option.value = c.name;
                option.textContent = c.tool_info?.name || c.name;
                select.appendChild(option);
            });

            // Set event listener
            select.addEventListener('change', (e) => {
                TerminalState.currentContainer = e.target.value;
                if (TerminalState.currentContainer) {
                    appendToTerminal(`Connected to ${TerminalState.currentContainer}`, 'system');
                }
            });
        }
    } catch (error) {
        console.error('Error loading terminal:', error);
    }
}

function clearTerminal() {
    const output = document.getElementById('terminal-output');
    if (output) {
        output.innerHTML = '';
    }
}

function appendToTerminal(text, type = 'output') {
    const output = document.getElementById('terminal-output');
    if (!output) return;

    const div = document.createElement('div');

    if (type === 'command') {
        div.className = 'terminal-command';
        div.textContent = text;
    } else if (type === 'error') {
        div.className = 'terminal-output terminal-error';
        div.textContent = text;
    } else if (type === 'system') {
        div.className = 'terminal-output';
        div.style.color = '#5af';
        div.textContent = `[SYSTEM] ${text}`;
    } else {
        div.className = 'terminal-output';
        div.textContent = text;
    }

    output.appendChild(div);
    output.scrollTop = output.scrollHeight;
}

async function executeTerminalCommand() {
    const input = document.getElementById('terminal-input');
    if (!input) return;

    const command = input.value.trim();
    if (!command) return;

    if (!TerminalState.currentContainer) {
        Toast.error('Please select a container first');
        return;
    }

    // Add to history
    TerminalState.commandHistory.push(command);
    TerminalState.historyIndex = TerminalState.commandHistory.length;

    // Display command
    appendToTerminal(command, 'command');

    // Clear input
    input.value = '';

    try {
        const response = await fetch(`/api/container/${TerminalState.currentContainer}/exec`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ command })
        });

        const data = await response.json();

        if (data.blocked) {
            appendToTerminal(data.error, 'error');
            Toast.warning(data.error);
        } else if (data.success) {
            if (data.stdout) {
                appendToTerminal(data.stdout);
            }
            if (data.stderr) {
                appendToTerminal(data.stderr, 'error');
            }
            if (data.exit_code !== 0) {
                appendToTerminal(`Exit code: ${data.exit_code}`, 'error');
            }
        } else {
            appendToTerminal(data.error || 'Command failed', 'error');
        }
    } catch (error) {
        appendToTerminal(`Error: ${error.message}`, 'error');
        Toast.error('Failed to execute command');
    }
}

function execQuickCommand(command) {
    const input = document.getElementById('terminal-input');
    if (input) {
        input.value = command;
        executeTerminalCommand();
    }
}

// ============================================================================
// TERMINAL INPUT HANDLERS
// ============================================================================
document.addEventListener('DOMContentLoaded', () => {
    const input = document.getElementById('terminal-input');
    if (input) {
        // Execute on Enter
        input.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                e.preventDefault();
                executeTerminalCommand();
            } else if (e.key === 'ArrowUp') {
                // Navigate history up
                e.preventDefault();
                if (TerminalState.historyIndex > 0) {
                    TerminalState.historyIndex--;
                    input.value = TerminalState.commandHistory[TerminalState.historyIndex] || '';
                }
            } else if (e.key === 'ArrowDown') {
                // Navigate history down
                e.preventDefault();
                if (TerminalState.historyIndex < TerminalState.commandHistory.length - 1) {
                    TerminalState.historyIndex++;
                    input.value = TerminalState.commandHistory[TerminalState.historyIndex] || '';
                } else {
                    TerminalState.historyIndex = TerminalState.commandHistory.length;
                    input.value = '';
                }
            }
        });
    }
});

// Make functions globally accessible
window.loadTerminalTab = loadTerminalTab;
window.clearTerminal = clearTerminal;
window.executeTerminalCommand = executeTerminalCommand;
window.execQuickCommand = execQuickCommand;
