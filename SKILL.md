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

# Render stats
./scripts/render.sh stats --data '{"stats":[{"label":"Users","value":"12.5K","change":"+12%"},{"label":"Revenue","value":"$45K","change":"+8%"}]}' -o stats.png
```

## Sharing Images Inline (Telegram/Messaging)

After rendering, send the image to users via the message tool.

**Important:** Images must be in `~/.openclaw/media/` to be sent via messaging.

```bash
# 1. Render to the media directory
./scripts/render.sh table --data '{"columns":["A","B"],"rows":[["1","2"]]}' -o ~/.openclaw/media/my-table.png

# 2. Send via message tool (in OpenClaw)
message(action=send, filePath=/home/ubuntu/.openclaw/media/my-table.png, caption="Here's the data", channel=telegram, to=<user_id>)
```

**Quick pattern for agents:**
```python
# Render → Send workflow
1. Generate image to ~/.openclaw/media/<name>.png
2. Use message tool with filePath to send inline
3. Image appears directly in chat
```

**Note:** Paths outside `~/.openclaw/media/` will be rejected by the message tool for security.

## Dependencies
- `/usr/bin/wkhtmltoimage` — HTML to image conversion
- `jq` — JSON parsing
- Chart.js (CDN) — For chart rendering
