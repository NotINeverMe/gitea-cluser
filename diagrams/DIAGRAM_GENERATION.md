# Diagram Generation Instructions

**Document Version:** 1.0
**Date:** 2025-10-05
**Purpose:** Instructions for rendering diagram sources to PNG/SVG formats suitable for CMMC/FedRAMP assessor submission packages.

---

## Overview

This directory contains authorization boundary diagrams (ABD), data flow diagrams (DFD), network topology diagrams, and evidence flow diagrams for the Gitea DevSecOps platform. All diagrams are provided in both **Mermaid** (`.mmd`) and **PlantUML** (`.puml`) source formats for maximum compatibility.

## Directory Structure

```
diagrams/
├── authorization-boundary.mmd          # Mermaid source for ABD
├── authorization-boundary.puml         # PlantUML source for ABD
├── data-flow.mmd                       # Mermaid source for DFD
├── data-flow.puml                      # PlantUML source for DFD
├── network-topology.mmd                # Mermaid source for network diagram
├── evidence-flow.mmd                   # Mermaid source for evidence flow
├── ASSET_INVENTORY.csv                 # Complete asset inventory
├── FLOW_INVENTORY.csv                  # Complete flow inventory
├── VALIDATION_CHECKLIST.md             # Assessor validation checklist
├── DIAGRAM_GENERATION.md               # This file
├── README.md                           # Overview and assumptions
└── rendered/                           # Generated images (created by scripts)
    ├── authorization-boundary.png
    ├── authorization-boundary.svg
    ├── data-flow.png
    ├── data-flow.svg
    ├── network-topology.png
    ├── network-topology.svg
    ├── evidence-flow.png
    └── evidence-flow.svg
```

---

## Rendering Methods

### Method 1: Mermaid CLI (Recommended for Automation)

#### Prerequisites
```bash
# Install Node.js (if not already installed)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install Mermaid CLI globally
npm install -g @mermaid-js/mermaid-cli
```

#### Render All Mermaid Diagrams
```bash
#!/bin/bash
# File: render-mermaid.sh

# Create output directory
mkdir -p rendered

# Render Authorization Boundary Diagram
mmdc -i authorization-boundary.mmd \
     -o rendered/authorization-boundary.png \
     -w 4096 -H 2304 \
     -t default \
     -b transparent

mmdc -i authorization-boundary.mmd \
     -o rendered/authorization-boundary.svg \
     -t default \
     -b transparent

# Render Data Flow Diagram
mmdc -i data-flow.mmd \
     -o rendered/data-flow.png \
     -w 4096 -H 2304 \
     -t default \
     -b transparent

mmdc -i data-flow.mmd \
     -o rendered/data-flow.svg \
     -t default \
     -b transparent

# Render Network Topology Diagram
mmdc -i network-topology.mmd \
     -o rendered/network-topology.png \
     -w 4096 -H 2304 \
     -t default \
     -b transparent

mmdc -i network-topology.mmd \
     -o rendered/network-topology.svg \
     -t default \
     -b transparent

# Render Evidence Flow Diagram
mmdc -i evidence-flow.mmd \
     -o rendered/evidence-flow.png \
     -w 4096 -H 2304 \
     -t default \
     -b transparent

mmdc -i evidence-flow.mmd \
     -o rendered/evidence-flow.svg \
     -t default \
     -b transparent

echo "All Mermaid diagrams rendered successfully to ./rendered/"
```

#### Execute Script
```bash
chmod +x render-mermaid.sh
./render-mermaid.sh
```

**Notes:**
- `-w 4096 -H 2304`: High resolution for assessor-grade documentation (16:9 aspect ratio)
- `-b transparent`: Transparent background for flexible document integration
- SVG format preserves vector quality for zooming

---

### Method 2: PlantUML (Recommended for High-Quality Output)

#### Prerequisites
```bash
# Install Java (required for PlantUML)
sudo apt-get update
sudo apt-get install -y default-jre

# Download PlantUML JAR
wget https://github.com/plantuml/plantuml/releases/download/v1.2024.7/plantuml-1.2024.7.jar -O plantuml.jar
```

#### Render All PlantUML Diagrams
```bash
#!/bin/bash
# File: render-plantuml.sh

# Create output directory
mkdir -p rendered

# Render Authorization Boundary Diagram (PNG)
java -jar plantuml.jar \
     -tpng \
     -DPLANTUML_LIMIT_SIZE=16384 \
     authorization-boundary.puml \
     -o rendered

# Render Authorization Boundary Diagram (SVG)
java -jar plantuml.jar \
     -tsvg \
     -DPLANTUML_LIMIT_SIZE=16384 \
     authorization-boundary.puml \
     -o rendered

# Render Data Flow Diagram (PNG)
java -jar plantuml.jar \
     -tpng \
     -DPLANTUML_LIMIT_SIZE=16384 \
     data-flow.puml \
     -o rendered

# Render Data Flow Diagram (SVG)
java -jar plantuml.jar \
     -tsvg \
     -DPLANTUML_LIMIT_SIZE=16384 \
     data-flow.puml \
     -o rendered

echo "All PlantUML diagrams rendered successfully to ./rendered/"
```

#### Execute Script
```bash
chmod +x render-plantuml.sh
./render-plantuml.sh
```

**Notes:**
- `-DPLANTUML_LIMIT_SIZE=16384`: Increase size limit for complex diagrams
- PNG output defaults to high DPI suitable for print
- SVG output is vector-based for infinite scaling

---

### Method 3: Docker (Isolated Environment)

#### Mermaid Docker
```bash
#!/bin/bash
# File: docker-render-mermaid.sh

docker run --rm -v $(pwd):/data minlag/mermaid-cli \
  -i /data/authorization-boundary.mmd \
  -o /data/rendered/authorization-boundary.png \
  -w 4096 -H 2304

docker run --rm -v $(pwd):/data minlag/mermaid-cli \
  -i /data/data-flow.mmd \
  -o /data/rendered/data-flow.png \
  -w 4096 -H 2304

docker run --rm -v $(pwd):/data minlag/mermaid-cli \
  -i /data/network-topology.mmd \
  -o /data/rendered/network-topology.png \
  -w 4096 -H 2304

docker run --rm -v $(pwd):/data minlag/mermaid-cli \
  -i /data/evidence-flow.mmd \
  -o /data/rendered/evidence-flow.png \
  -w 4096 -H 2304

echo "Mermaid Docker rendering complete"
```

#### PlantUML Docker
```bash
#!/bin/bash
# File: docker-render-plantuml.sh

docker run --rm -v $(pwd):/data plantuml/plantuml \
  -tpng -o /data/rendered /data/authorization-boundary.puml

docker run --rm -v $(pwd):/data plantuml/plantuml \
  -tpng -o /data/rendered /data/data-flow.puml

docker run --rm -v $(pwd):/data plantuml/plantuml \
  -tsvg -o /data/rendered /data/authorization-boundary.puml

docker run --rm -v $(pwd):/data plantuml/plantuml \
  -tsvg -o /data/rendered /data/data-flow.puml

echo "PlantUML Docker rendering complete"
```

---

### Method 4: Online Editors (Manual)

#### Mermaid Live Editor
1. Navigate to: https://mermaid.live/
2. Copy contents of `.mmd` file into the editor
3. Click "Actions" → "Download PNG" or "Download SVG"
4. Save to `rendered/` directory

#### PlantUML Online Server
1. Navigate to: https://www.plantuml.com/plantuml/uml/
2. Copy contents of `.puml` file into the editor
3. Click PNG or SVG button to download
4. Save to `rendered/` directory

**Warning:** Do not use online editors for CUI-classified diagrams in production. Use offline/Docker methods only.

---

## Validation After Rendering

### Visual Inspection
```bash
# View PNG files
xdg-open rendered/authorization-boundary.png
xdg-open rendered/data-flow.png
xdg-open rendered/network-topology.png
xdg-open rendered/evidence-flow.png
```

### Quality Checks
- [ ] All text is legible at 100% zoom
- [ ] Asset IDs and Flow IDs are readable
- [ ] Color coding is consistent and accessible
- [ ] Legend is complete and not cut off
- [ ] No rendering artifacts or overlapping elements
- [ ] Arrows point to correct assets
- [ ] Zone boundaries are clearly visible

### File Size Validation
```bash
# Check file sizes (PNG should be <5MB, SVG <1MB)
ls -lh rendered/

# Expected output:
# authorization-boundary.png: ~2-4 MB
# authorization-boundary.svg: ~200-500 KB
# data-flow.png: ~2-4 MB
# data-flow.svg: ~300-600 KB
```

---

## Embedding in Documentation

### Markdown
```markdown
## Authorization Boundary Diagram
![Authorization Boundary Diagram](rendered/authorization-boundary.png)

## Data Flow Diagram
![Data Flow Diagram](rendered/data-flow.png)
```

### LaTeX (for SSP documents)
```latex
\begin{figure}[h]
\centering
\includegraphics[width=\textwidth]{rendered/authorization-boundary.png}
\caption{Authorization Boundary Diagram - Gitea DevSecOps Platform}
\label{fig:abd}
\end{figure}
```

### Microsoft Word
1. Insert → Pictures → Select `rendered/authorization-boundary.png`
2. Right-click → Wrap Text → "In Line with Text" or "Tight"
3. Add caption: References → Insert Caption

### Google Docs
1. Insert → Image → Upload from computer
2. Select `rendered/authorization-boundary.png`
3. Add caption below image

---

## Updating Diagrams

### Workflow
1. Edit source files (`.mmd` or `.puml`)
2. Re-run rendering script
3. Validate output visually
4. Update `ASSET_INVENTORY.csv` or `FLOW_INVENTORY.csv` if assets/flows changed
5. Re-run `VALIDATION_CHECKLIST.md` review
6. Commit changes to version control

### Version Control
```bash
# Initialize git repository (if not already done)
git init

# Track diagram sources and CSVs (not rendered images)
git add *.mmd *.puml *.csv *.md
git commit -m "Update authorization boundary diagram with new scanner assets"

# Add rendered/ to .gitignore (regenerate on demand)
echo "rendered/" >> .gitignore
git add .gitignore
git commit -m "Ignore rendered images (regenerate on demand)"
```

---

## Troubleshooting

### Mermaid CLI Errors

**Error:** `Error: Cannot find module 'puppeteer-core'`
```bash
# Reinstall Mermaid CLI with Chromium
npm install -g @mermaid-js/mermaid-cli
```

**Error:** `Diagram too large`
```bash
# Increase size limit
mmdc -i diagram.mmd -o output.png --width 8192 --height 4608
```

### PlantUML Errors

**Error:** `java.lang.OutOfMemoryError`
```bash
# Increase Java heap size
java -Xmx2048m -jar plantuml.jar -tpng diagram.puml
```

**Error:** `Syntax error at line X`
- Check for unescaped special characters in labels
- Ensure all brackets and quotes are balanced
- Validate with online editor first

### Docker Errors

**Error:** `Permission denied`
```bash
# Fix file permissions
sudo chown -R $USER:$USER rendered/
chmod -R 755 rendered/
```

**Error:** `Cannot pull image`
```bash
# Pull images manually
docker pull minlag/mermaid-cli:latest
docker pull plantuml/plantuml:latest
```

---

## Automation with CI/CD

### GitHub Actions Workflow
```yaml
# File: .github/workflows/render-diagrams.yml
name: Render Diagrams

on:
  push:
    paths:
      - 'diagrams/*.mmd'
      - 'diagrams/*.puml'

jobs:
  render:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '20'

      - name: Install Mermaid CLI
        run: npm install -g @mermaid-js/mermaid-cli

      - name: Render Mermaid Diagrams
        run: |
          cd diagrams
          ./render-mermaid.sh

      - name: Upload Rendered Diagrams
        uses: actions/upload-artifact@v3
        with:
          name: rendered-diagrams
          path: diagrams/rendered/
```

### GitLab CI Pipeline
```yaml
# File: .gitlab-ci.yml
render-diagrams:
  stage: build
  image: node:20
  before_script:
    - npm install -g @mermaid-js/mermaid-cli
  script:
    - cd diagrams
    - chmod +x render-mermaid.sh
    - ./render-mermaid.sh
  artifacts:
    paths:
      - diagrams/rendered/
    expire_in: 30 days
  only:
    changes:
      - diagrams/*.mmd
      - diagrams/*.puml
```

---

## Assessor Submission Package

### Package Contents
```bash
# Create submission package
tar -czf gitea-devsecops-diagrams-$(date +%Y%m%d).tar.gz \
  *.mmd *.puml *.csv *.md rendered/

# Verify package
tar -tzf gitea-devsecops-diagrams-*.tar.gz
```

### ZIP Alternative (Windows-compatible)
```bash
zip -r gitea-devsecops-diagrams-$(date +%Y%m%d).zip \
  *.mmd *.puml *.csv *.md rendered/
```

### Package Checklist
- [ ] All source files (`.mmd`, `.puml`)
- [ ] All rendered images (PNG and SVG)
- [ ] `ASSET_INVENTORY.csv`
- [ ] `FLOW_INVENTORY.csv`
- [ ] `VALIDATION_CHECKLIST.md`
- [ ] `README.md` with assumptions
- [ ] This file (`DIAGRAM_GENERATION.md`)

---

## Support and References

### Mermaid Documentation
- Official Docs: https://mermaid.js.org/
- Live Editor: https://mermaid.live/
- CLI Docs: https://github.com/mermaid-js/mermaid-cli

### PlantUML Documentation
- Official Docs: https://plantuml.com/
- Online Server: https://www.plantuml.com/plantuml/
- GitHub Releases: https://github.com/plantuml/plantuml/releases

### Standards References
- NIST SP 800-171 Rev. 2: https://doi.org/10.6028/NIST.SP.800-171r2
- CMMC 2.0 Model: https://dodcio.defense.gov/CMMC/Model/
- NIST SP 800-53 Rev. 5: https://doi.org/10.6028/NIST.SP.800-53r5

---

**End of Diagram Generation Instructions**
