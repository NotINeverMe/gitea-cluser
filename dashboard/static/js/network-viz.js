/**
 * DevSecOps Dashboard - Network Visualization Module
 * D3.js-based network topology visualization
 */

// ============================================================================
// NETWORK VISUALIZATION
// ============================================================================
async function loadNetworkTopology(networkName) {
    try {
        const response = await fetch(`/api/network/${networkName}/topology`);
        const data = await response.json();

        visualizeNetworkTopology(data);
    } catch (error) {
        console.error('Error loading network topology:', error);
        Toast.error('Failed to load network topology');
    }
}

function visualizeNetworkTopology(data) {
    const container = document.getElementById('network-topology-viz');
    if (!container) return;

    // Clear previous visualization
    container.innerHTML = '';

    const width = container.clientWidth;
    const height = container.clientHeight;

    // Create SVG
    const svg = d3.select(container)
        .append('svg')
        .attr('width', width)
        .attr('height', height);

    // Create force simulation
    const simulation = d3.forceSimulation(data.nodes)
        .force('link', d3.forceLink(data.edges).id(d => d.id).distance(150))
        .force('charge', d3.forceManyBody().strength(-300))
        .force('center', d3.forceCenter(width / 2, height / 2));

    // Create links
    const link = svg.append('g')
        .selectAll('line')
        .data(data.edges)
        .enter()
        .append('line')
        .attr('class', 'network-link')
        .attr('stroke', '#30363d')
        .attr('stroke-width', 2);

    // Create nodes
    const node = svg.append('g')
        .selectAll('g')
        .data(data.nodes)
        .enter()
        .append('g')
        .attr('class', d => `network-node ${d.type}`)
        .call(d3.drag()
            .on('start', dragstarted)
            .on('drag', dragged)
            .on('end', dragended));

    // Add circles to nodes
    node.append('circle')
        .attr('r', d => d.type === 'network' ? 30 : 20)
        .attr('fill', d => d.type === 'network' ? '#bc8cff' : '#58a6ff')
        .attr('stroke', d => d.type === 'network' ? '#bc8cff' : '#58a6ff');

    // Add labels
    node.append('text')
        .attr('class', 'network-label')
        .attr('text-anchor', 'middle')
        .attr('dy', '.35em')
        .attr('fill', '#c9d1d9')
        .style('font-size', '10px')
        .style('font-weight', '600')
        .text(d => d.label);

    // Add IP address labels for containers
    node.filter(d => d.type === 'container' && d.ipv4)
        .append('text')
        .attr('class', 'network-label')
        .attr('text-anchor', 'middle')
        .attr('dy', '25px')
        .attr('fill', '#8b949e')
        .style('font-size', '9px')
        .text(d => d.ipv4.split('/')[0]);

    // Update positions on simulation tick
    simulation.on('tick', () => {
        link
            .attr('x1', d => d.source.x)
            .attr('y1', d => d.source.y)
            .attr('x2', d => d.target.x)
            .attr('y2', d => d.target.y);

        node.attr('transform', d => `translate(${d.x},${d.y})`);
    });

    // Drag functions
    function dragstarted(event, d) {
        if (!event.active) simulation.alphaTarget(0.3).restart();
        d.fx = d.x;
        d.fy = d.y;
    }

    function dragged(event, d) {
        d.fx = event.x;
        d.fy = event.y;
    }

    function dragended(event, d) {
        if (!event.active) simulation.alphaTarget(0);
        d.fx = null;
        d.fy = null;
    }

    // Add tooltip
    node.on('mouseover', function(event, d) {
        d3.select(this).select('circle')
            .attr('stroke-width', 4);
    }).on('mouseout', function(event, d) {
        d3.select(this).select('circle')
            .attr('stroke-width', 2);
    });
}

// Make functions globally accessible
window.loadNetworkTopology = loadNetworkTopology;
window.visualizeNetworkTopology = visualizeNetworkTopology;
