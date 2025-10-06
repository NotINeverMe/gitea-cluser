#!/bin/bash
# Mermaid Diagram Rendering Script
# Requires: @mermaid-js/mermaid-cli (npm install -g @mermaid-js/mermaid-cli)

set -e  # Exit on error

echo "=== Gitea DevSecOps Platform - Mermaid Diagram Rendering ==="
echo "Date: $(date)"
echo ""

# Create output directory
mkdir -p rendered

# Check if mmdc is installed
if ! command -v mmdc &> /dev/null; then
    echo "ERROR: Mermaid CLI (mmdc) not found."
    echo "Install with: npm install -g @mermaid-js/mermaid-cli"
    exit 1
fi

echo "Mermaid CLI version: $(mmdc --version)"
echo ""

# Render Authorization Boundary Diagram
echo "[1/4] Rendering Authorization Boundary Diagram..."
mmdc -i authorization-boundary.mmd \
     -o rendered/authorization-boundary.png \
     -w 4096 -H 2304 \
     -t default \
     -b transparent \
     && echo "  ✓ PNG created: rendered/authorization-boundary.png"

mmdc -i authorization-boundary.mmd \
     -o rendered/authorization-boundary.svg \
     -t default \
     -b transparent \
     && echo "  ✓ SVG created: rendered/authorization-boundary.svg"

# Render Data Flow Diagram
echo "[2/4] Rendering Data Flow Diagram..."
mmdc -i data-flow.mmd \
     -o rendered/data-flow.png \
     -w 4096 -H 2304 \
     -t default \
     -b transparent \
     && echo "  ✓ PNG created: rendered/data-flow.png"

mmdc -i data-flow.mmd \
     -o rendered/data-flow.svg \
     -t default \
     -b transparent \
     && echo "  ✓ SVG created: rendered/data-flow.svg"

# Render Network Topology Diagram
echo "[3/4] Rendering Network Topology Diagram..."
mmdc -i network-topology.mmd \
     -o rendered/network-topology.png \
     -w 4096 -H 2304 \
     -t default \
     -b transparent \
     && echo "  ✓ PNG created: rendered/network-topology.png"

mmdc -i network-topology.mmd \
     -o rendered/network-topology.svg \
     -t default \
     -b transparent \
     && echo "  ✓ SVG created: rendered/network-topology.svg"

# Render Evidence Flow Diagram
echo "[4/4] Rendering Evidence Flow Diagram..."
mmdc -i evidence-flow.mmd \
     -o rendered/evidence-flow.png \
     -w 4096 -H 2304 \
     -t default \
     -b transparent \
     && echo "  ✓ PNG created: rendered/evidence-flow.png"

mmdc -i evidence-flow.mmd \
     -o rendered/evidence-flow.svg \
     -t default \
     -b transparent \
     && echo "  ✓ SVG created: rendered/evidence-flow.svg"

echo ""
echo "=== Rendering Complete ==="
echo "Output directory: $(pwd)/rendered/"
echo ""
echo "Generated files:"
ls -lh rendered/
echo ""
echo "Next steps:"
echo "  1. Validate diagrams visually: xdg-open rendered/*.png"
echo "  2. Review VALIDATION_CHECKLIST.md"
echo "  3. Package for assessor: tar -czf diagrams-$(date +%Y%m%d).tar.gz *.mmd *.puml *.csv *.md rendered/"
