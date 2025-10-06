#!/bin/bash
# PlantUML Diagram Rendering Script
# Requires: Java Runtime Environment and plantuml.jar

set -e  # Exit on error

echo "=== Gitea DevSecOps Platform - PlantUML Diagram Rendering ==="
echo "Date: $(date)"
echo ""

# Create output directory
mkdir -p rendered

# Check if Java is installed
if ! command -v java &> /dev/null; then
    echo "ERROR: Java not found. PlantUML requires Java Runtime Environment."
    echo "Install with: sudo apt-get install default-jre"
    exit 1
fi

echo "Java version: $(java -version 2>&1 | head -n 1)"
echo ""

# Download PlantUML if not present
PLANTUML_JAR="plantuml.jar"
if [ ! -f "$PLANTUML_JAR" ]; then
    echo "PlantUML JAR not found. Downloading latest version..."
    wget https://github.com/plantuml/plantuml/releases/download/v1.2024.7/plantuml-1.2024.7.jar -O plantuml.jar
    echo "  ✓ Downloaded plantuml.jar"
    echo ""
fi

# Render Authorization Boundary Diagram
echo "[1/2] Rendering Authorization Boundary Diagram..."

echo "  Rendering PNG..."
java -jar $PLANTUML_JAR \
     -tpng \
     -DPLANTUML_LIMIT_SIZE=16384 \
     authorization-boundary.puml \
     -o rendered \
     && echo "  ✓ PNG created: rendered/authorization-boundary.png"

echo "  Rendering SVG..."
java -jar $PLANTUML_JAR \
     -tsvg \
     -DPLANTUML_LIMIT_SIZE=16384 \
     authorization-boundary.puml \
     -o rendered \
     && echo "  ✓ SVG created: rendered/authorization-boundary.svg"

# Render Data Flow Diagram
echo "[2/2] Rendering Data Flow Diagram..."

echo "  Rendering PNG..."
java -jar $PLANTUML_JAR \
     -tpng \
     -DPLANTUML_LIMIT_SIZE=16384 \
     data-flow.puml \
     -o rendered \
     && echo "  ✓ PNG created: rendered/data-flow.png"

echo "  Rendering SVG..."
java -jar $PLANTUML_JAR \
     -tsvg \
     -DPLANTUML_LIMIT_SIZE=16384 \
     data-flow.puml \
     -o rendered \
     && echo "  ✓ SVG created: rendered/data-flow.svg"

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
