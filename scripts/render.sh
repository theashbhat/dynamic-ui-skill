#!/bin/bash
# Dynamic UI Renderer - Converts JSON data to images via HTML templates

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$SKILL_DIR/templates"
THEMES_DIR="$SKILL_DIR/themes"

# Defaults
TEMPLATE=""
DATA=""
STYLE="modern"
OUTPUT=""
WIDTH="800"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --data|--input)
            DATA="$2"
            shift 2
            ;;
        --style)
            STYLE="$2"
            shift 2
            ;;
        --output|-o)
            OUTPUT="$2"
            shift 2
            ;;
        --width)
            WIDTH="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "$TEMPLATE" ]]; then
                TEMPLATE="$1"
            fi
            shift
            ;;
    esac
done

# Read from stdin if no data provided
if [[ -z "$DATA" ]]; then
    if [[ ! -t 0 ]]; then
        DATA=$(cat)
    else
        echo "Error: No data provided. Use --data or pipe JSON to stdin." >&2
        exit 1
    fi
fi

# Validate template
if [[ -z "$TEMPLATE" ]]; then
    echo "Error: No template specified." >&2
    echo "Usage: render.sh <template> --data '<json>' [--style theme] [--output file]" >&2
    exit 1
fi

TEMPLATE_FILE="$TEMPLATES_DIR/${TEMPLATE}.html"
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "Error: Template '$TEMPLATE' not found at $TEMPLATE_FILE" >&2
    exit 1
fi

THEME_FILE="$THEMES_DIR/${STYLE}.css"
if [[ ! -f "$THEME_FILE" ]]; then
    echo "Error: Theme '$STYLE' not found at $THEME_FILE" >&2
    exit 1
fi

# Create temp directory for processing
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy theme CSS to temp
cp "$THEME_FILE" "$TEMP_DIR/theme.css"

# Generate content based on template type
generate_table() {
    local data="$1"
    
    # Build table HTML
    TABLE_HEADER=""
    for col in $(echo "$data" | jq -r '.columns[]'); do
        TABLE_HEADER+="<th>$col</th>"
    done
    
    TABLE_BODY=""
    ROW_COUNT=$(echo "$data" | jq '.rows | length')
    for ((i=0; i<ROW_COUNT; i++)); do
        TABLE_BODY+="<tr>"
        COL_COUNT=$(echo "$data" | jq ".rows[$i] | length")
        for ((j=0; j<COL_COUNT; j++)); do
            CELL=$(echo "$data" | jq -r ".rows[$i][$j]")
            TABLE_BODY+="<td>$CELL</td>"
        done
        TABLE_BODY+="</tr>"
    done
    
    echo "$TABLE_HEADER" > "$TEMP_DIR/header.html"
    echo "$TABLE_BODY" > "$TEMP_DIR/body.html"
}

generate_chart() {
    local data="$1"
    local title=$(echo "$data" | jq -r '.title // "Chart"')
    echo "$title" > "$TEMP_DIR/title.txt"
    
    # Get max value for scaling
    local max_val=$(echo "$data" | jq '[.values[]] | max')
    local count=$(echo "$data" | jq '.labels | length')
    
    BARS_HTML=""
    for ((i=0; i<count; i++)); do
        local label=$(echo "$data" | jq -r ".labels[$i]")
        local value=$(echo "$data" | jq -r ".values[$i]")
        # Scale height to max 220px
        local height=$(echo "$value $max_val" | awk '{printf "%.0f", ($1/$2)*220}')
        BARS_HTML+="<div class=\"bar-wrapper\"><div class=\"bar\" style=\"height: ${height}px;\"><span class=\"bar-value\">$value</span></div><div class=\"bar-label\">$label</div></div>"
    done
    echo "$BARS_HTML" > "$TEMP_DIR/bars.html"
}

generate_stats() {
    local data="$1"
    STATS_HTML=""
    STAT_COUNT=$(echo "$data" | jq '.stats | length')
    for ((i=0; i<STAT_COUNT; i++)); do
        LABEL=$(echo "$data" | jq -r ".stats[$i].label")
        VALUE=$(echo "$data" | jq -r ".stats[$i].value")
        CHANGE=$(echo "$data" | jq -r ".stats[$i].change // \"\"")
        
        CHANGE_CLASS="neutral"
        if [[ "$CHANGE" == +* ]]; then
            CHANGE_CLASS="positive"
        elif [[ "$CHANGE" == -* ]]; then
            CHANGE_CLASS="negative"
        fi
        
        STATS_HTML+="<div class=\"stat-card\"><div class=\"stat-label\">$LABEL</div><div class=\"stat-value\">$VALUE</div><div class=\"stat-change $CHANGE_CLASS\">$CHANGE</div></div>"
    done
    echo "$STATS_HTML" > "$TEMP_DIR/stats.html"
}

generate_card() {
    local data="$1"
    TITLE=$(echo "$data" | jq -r '.title // ""')
    SUBTITLE=$(echo "$data" | jq -r '.subtitle // ""')
    BODY=$(echo "$data" | jq -r '.body // ""')
    STATUS=$(echo "$data" | jq -r '.status // ""')
    IMAGE=$(echo "$data" | jq -r '.image // ""')
    
    IMAGE_HTML=""
    if [[ -n "$IMAGE" && "$IMAGE" != "null" ]]; then
        IMAGE_HTML="<img src=\"$IMAGE\" class=\"card-image\" />"
    fi
    
    STATUS_HTML=""
    if [[ -n "$STATUS" && "$STATUS" != "null" ]]; then
        STATUS_HTML="<div class=\"card-status status-$STATUS\"></div>"
    fi
    
    echo "$TITLE" > "$TEMP_DIR/title.txt"
    echo "$SUBTITLE" > "$TEMP_DIR/subtitle.txt"
    echo "$BODY" > "$TEMP_DIR/body.txt"
    echo "$STATUS_HTML" > "$TEMP_DIR/status.html"
    echo "$IMAGE_HTML" > "$TEMP_DIR/image.html"
}

generate_dashboard() {
    local data="$1"
    DASH_TITLE=$(echo "$data" | jq -r '.title // "Dashboard"')
    WIDGETS_HTML=""
    
    WIDGET_COUNT=$(echo "$data" | jq '.widgets | length')
    for ((i=0; i<WIDGET_COUNT; i++)); do
        WIDGET_TYPE=$(echo "$data" | jq -r ".widgets[$i].type")
        WIDGET_DATA=$(echo "$data" | jq -c ".widgets[$i]")
        
        case $WIDGET_TYPE in
            stat|stats)
                W_LABEL=$(echo "$WIDGET_DATA" | jq -r '.label // .stats[0].label // ""')
                W_VALUE=$(echo "$WIDGET_DATA" | jq -r '.value // .stats[0].value // ""')
                W_CHANGE=$(echo "$WIDGET_DATA" | jq -r '.change // .stats[0].change // ""')
                CHANGE_CLASS="neutral"
                [[ "$W_CHANGE" == +* ]] && CHANGE_CLASS="positive"
                [[ "$W_CHANGE" == -* ]] && CHANGE_CLASS="negative"
                WIDGETS_HTML+="<div class=\"widget widget-stat\"><div class=\"stat-label\">$W_LABEL</div><div class=\"stat-value\">$W_VALUE</div><div class=\"stat-change $CHANGE_CLASS\">$W_CHANGE</div></div>"
                ;;
            table)
                TH=""
                for col in $(echo "$WIDGET_DATA" | jq -r '.columns[]' 2>/dev/null); do
                    TH+="<th>$col</th>"
                done
                TB=""
                W_ROW_COUNT=$(echo "$WIDGET_DATA" | jq '.rows | length' 2>/dev/null || echo 0)
                for ((r=0; r<W_ROW_COUNT; r++)); do
                    TB+="<tr>"
                    W_COL_COUNT=$(echo "$WIDGET_DATA" | jq ".rows[$r] | length")
                    for ((c=0; c<W_COL_COUNT; c++)); do
                        CELL=$(echo "$WIDGET_DATA" | jq -r ".rows[$r][$c]")
                        TB+="<td>$CELL</td>"
                    done
                    TB+="</tr>"
                done
                WIDGETS_HTML+="<div class=\"widget widget-table\"><table><thead><tr>$TH</tr></thead><tbody>$TB</tbody></table></div>"
                ;;
            chart)
                W_LABELS=$(echo "$WIDGET_DATA" | jq -c '.labels // []')
                W_VALUES=$(echo "$WIDGET_DATA" | jq -c '.values // []')
                W_TITLE=$(echo "$WIDGET_DATA" | jq -r '.title // "Chart"')
                CHART_ID="chart_$i"
                WIDGETS_HTML+="<div class=\"widget widget-chart\"><canvas id=\"$CHART_ID\" width=\"350\" height=\"200\"></canvas><script>new Chart(document.getElementById('$CHART_ID'), {type: 'bar',data: {labels: $W_LABELS,datasets: [{label: '$W_TITLE',data: $W_VALUES,backgroundColor: 'rgba(102, 126, 234, 0.8)',borderColor: 'rgba(102, 126, 234, 1)',borderWidth: 1}]},options: {responsive: false,plugins: { legend: { display: false } }}});</script></div>"
                ;;
        esac
    done
    
    echo "$DASH_TITLE" > "$TEMP_DIR/dashtitle.txt"
    echo "$WIDGETS_HTML" > "$TEMP_DIR/widgets.html"
}

# Build final HTML using node for proper templating
build_html() {
    local template_type="$1"
    local theme_css=$(cat "$TEMP_DIR/theme.css")
    
    case $template_type in
        table)
            local header=$(cat "$TEMP_DIR/header.html")
            local body=$(cat "$TEMP_DIR/body.html")
            cat "$TEMPLATE_FILE" | \
                awk -v css="$theme_css" '{gsub(/\{\{THEME_CSS\}\}/, css); print}' | \
                awk -v h="$header" '{gsub(/\{\{TABLE_HEADER\}\}/, h); print}' | \
                awk -v b="$body" '{gsub(/\{\{TABLE_BODY\}\}/, b); print}' > "$TEMP_DIR/render.html"
            ;;
        chart-bar)
            local title=$(cat "$TEMP_DIR/title.txt")
            local bars=$(cat "$TEMP_DIR/bars.html")
            cat "$TEMPLATE_FILE" | \
                awk -v css="$theme_css" '{gsub(/\{\{THEME_CSS\}\}/, css); print}' | \
                awk -v t="$title" '{gsub(/\{\{TITLE\}\}/, t); print}' | \
                awk -v b="$bars" '{gsub(/\{\{BARS_HTML\}\}/, b); print}' > "$TEMP_DIR/render.html"
            ;;
        stats)
            local stats=$(cat "$TEMP_DIR/stats.html")
            cat "$TEMPLATE_FILE" | \
                awk -v css="$theme_css" '{gsub(/\{\{THEME_CSS\}\}/, css); print}' | \
                awk -v s="$stats" '{gsub(/\{\{STATS_HTML\}\}/, s); print}' > "$TEMP_DIR/render.html"
            ;;
        card)
            local title=$(cat "$TEMP_DIR/title.txt")
            local subtitle=$(cat "$TEMP_DIR/subtitle.txt")
            local body=$(cat "$TEMP_DIR/body.txt")
            local status=$(cat "$TEMP_DIR/status.html")
            local image=$(cat "$TEMP_DIR/image.html")
            cat "$TEMPLATE_FILE" | \
                awk -v css="$theme_css" '{gsub(/\{\{THEME_CSS\}\}/, css); print}' | \
                awk -v t="$title" '{gsub(/\{\{TITLE\}\}/, t); print}' | \
                awk -v s="$subtitle" '{gsub(/\{\{SUBTITLE\}\}/, s); print}' | \
                awk -v b="$body" '{gsub(/\{\{BODY\}\}/, b); print}' | \
                awk -v st="$status" '{gsub(/\{\{STATUS_HTML\}\}/, st); print}' | \
                awk -v im="$image" '{gsub(/\{\{IMAGE_HTML\}\}/, im); print}' > "$TEMP_DIR/render.html"
            ;;
        dashboard)
            local dashtitle=$(cat "$TEMP_DIR/dashtitle.txt")
            local widgets=$(cat "$TEMP_DIR/widgets.html")
            cat "$TEMPLATE_FILE" | \
                awk -v css="$theme_css" '{gsub(/\{\{THEME_CSS\}\}/, css); print}' | \
                awk -v t="$dashtitle" '{gsub(/\{\{DASH_TITLE\}\}/, t); print}' | \
                awk -v w="$widgets" '{gsub(/\{\{WIDGETS_HTML\}\}/, w); print}' > "$TEMP_DIR/render.html"
            ;;
    esac
}

# Process template based on type
case $TEMPLATE in
    table)
        generate_table "$DATA"
        build_html table
        ;;
    chart-bar)
        generate_chart "$DATA"
        build_html chart-bar
        ;;
    stats)
        generate_stats "$DATA"
        build_html stats
        ;;
    card)
        generate_card "$DATA"
        build_html card
        ;;
    dashboard)
        generate_dashboard "$DATA"
        build_html dashboard
        ;;
    *)
        echo "Error: Unknown template type '$TEMPLATE'" >&2
        exit 1
        ;;
esac

# Determine output path
if [[ -z "$OUTPUT" ]]; then
    OUTPUT_FILE="$TEMP_DIR/output.png"
else
    OUTPUT_FILE="$OUTPUT"
fi

# Render with wkhtmltoimage
/usr/bin/wkhtmltoimage \
    --quiet \
    --width "$WIDTH" \
    --enable-javascript \
    --javascript-delay 500 \
    --format png \
    "$TEMP_DIR/render.html" \
    "$OUTPUT_FILE"

# If no output specified, output base64 to stdout
if [[ -z "$OUTPUT" ]]; then
    base64 -w0 "$OUTPUT_FILE"
else
    echo "$OUTPUT_FILE"
fi
