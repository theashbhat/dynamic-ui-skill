---
name: dynamic-ui
description: Render tables, charts, stats, cards, and dashboards as images using HTML templates and wkhtmltoimage.
metadata:
  openclaw:
    requires:
      bins: ["wkhtmltoimage", "jq"]
    install:
      - id: apt
        kind: apt
        packages: ["wkhtmltopdf"]
        bins: ["wkhtmltoimage"]
        label: "Install wkhtmltoimage (apt)"
---

# Dynamic UI Skill

Render dynamic visual content (tables, charts, stats, cards, dashboards) as images using HTML templates and wkhtmltoimage.

## Triggers
- "render", "visualize", "chart", "dashboard", "dynamic-ui"

## Usage

```bash
# Basic usage
./scripts/render.sh <template> --data '<json>'

# With options
./scripts/render.sh table --data '{"columns":["A","B"],"rows":[["1","2"]]}' --style dark --output out.png

# From stdin
echo '{"labels":["Q1","Q2"],"values":[100,200]}' | ./scripts/render.sh chart-bar --style modern
```

## Templates

| Template | Description | Input Schema |
|----------|-------------|--------------|
| `table` | Data tables | `{"columns": [...], "rows": [[...], ...]}` |
| `chart-bar` | Bar charts | `{"labels": [...], "values": [...], "title": "..."}` |
| `chart-line` | Line charts | `{"labels": [...], "values": [...], "title": "...", "subtitle": "...", "y_suffix": "%"}` |
| `stats` | KPI cards | `{"stats": [{"label": "...", "value": "...", "change": "..."}]}` |
| `card` | Info card | `{"title": "...", "subtitle": "...", "body": "...", "status": "green\|yellow\|red"}` |
| `dashboard` | Composite | `{"title": "...", "widgets": [{"type": "stat\|table\|chart", ...}]}` |

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--data`, `--input` | JSON data (or use stdin) | - |
| `--style` | Theme: modern, dark, minimal | modern |
| `--output`, `-o` | Output path | stdout (base64) |
| `--width` | Image width in pixels | 800 |

## Themes

- **modern** — Purple/blue gradients, shadows, rounded corners
- **dark** — Dark background, light text, subtle borders
- **minimal** — Clean white, thin borders

## Examples

```bash
# Render a table
./scripts/render.sh table --data '{"columns":["Name","Score"],"rows":[["Alice","95"],["Bob","87"]]}' -o table.png

# Render a bar chart
./scripts/render.sh chart-bar --data '{"labels":["Jan","Feb","Mar"],"values":[120,150,180],"title":"Monthly Sales"}' --style dark -o chart.png

# Render a line chart (single series)
./scripts/render.sh chart-line --data '{"labels":["W1","W2","W3","W4"],"values":[10,12,15,25],"title":"Growth","subtitle":"Week over week","y_suffix":"%"}' --style dark -o line.png

# Render a line chart (multi-series)
./scripts/render.sh chart-line --data '{"labels":["Q1","Q2","Q3","Q4"],"datasets":[{"label":"Revenue","values":[100,150,200,350]},{"label":"Costs","values":[80,90,100,120]}],"title":"Revenue vs Costs"}' -o multi.png

# Render stats
./scripts/render.sh stats --data '{"stats":[{"label":"Users","value":"12.5K","change":"+12%"},{"label":"Revenue","value":"$45K","change":"+8%"}]}' -o stats.png
```

## ⚠️ ALWAYS Send Images Inline

**After rendering, you MUST send the image inline using the message tool.** Don't just save to disk — the user can't see it unless you send it!

### Required Workflow:
```bash
# 1. ALWAYS render to ~/.openclaw/media/
./scripts/render.sh table --data '...' -o ~/.openclaw/media/my-table.png

# 2. IMMEDIATELY send inline via message tool
message(action=send, filePath=/home/ubuntu/.openclaw/media/my-table.png, caption="Caption", channel=telegram, to=<user_id>)
```

### Key Rules:
1. **Always save to `~/.openclaw/media/`** — other paths won't work
2. **Always call message tool after render** — user can't see disk files
3. **Use descriptive captions** — helps user understand the visual
4. **Send immediately** — don't wait for user to ask

### Example (complete flow):
```bash
# Render
echo '{"title":"My Data","columns":["A","B"],"rows":[["1","2"]]}' | \
  ./scripts/render.sh table -o ~/.openclaw/media/data.png

# Send (do this EVERY time!)
message(action=send, filePath=/home/ubuntu/.openclaw/media/data.png, caption="Here's your data", channel=telegram, to=USER_ID)
```

## Dependencies
- `/usr/bin/wkhtmltoimage` — HTML to image conversion
- `jq` — JSON parsing
- Chart.js (CDN) — For chart rendering
