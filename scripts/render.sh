#!/bin/bash
# Dynamic UI Renderer - Converts JSON data to images via HTML templates

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# HTML entity escaping for user-supplied text
escape_html() {
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
}

# Validate image URL (block dangerous protocols)
validate_image_url() {
    local url="$1"
    # Block file://, javascript:, data: (except data:image), and vbscript:
    if [[ "$url" =~ ^(file:|javascript:|vbscript:) ]]; then
        echo ""
        return
    fi
    if [[ "$url" =~ ^data: ]] && [[ ! "$url" =~ ^data:image/ ]]; then
        echo ""
        return
    fi
    echo "$url"
}
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
    
    # Extract title if present
    local title=$(echo "$data" | jq -r '.title // ""')
    if [[ -n "$title" && "$title" != "null" ]]; then
        title=$(escape_html "$title")
        echo "<div class=\"page-title\">$title</div>" > "$TEMP_DIR/title.html"
    else
        echo "" > "$TEMP_DIR/title.html"
    fi
    
    # Build table HTML
    TABLE_HEADER=""
    for col in $(echo "$data" | jq -r '.columns[]'); do
        col=$(escape_html "$col")
        TABLE_HEADER+="<th>$col</th>"
    done
    
    TABLE_BODY=""
    ROW_COUNT=$(echo "$data" | jq '.rows | length')
    for ((i=0; i<ROW_COUNT; i++)); do
        TABLE_BODY+="<tr>"
        COL_COUNT=$(echo "$data" | jq ".rows[$i] | length")
        for ((j=0; j<COL_COUNT; j++)); do
            CELL=$(echo "$data" | jq -r ".rows[$i][$j]")
            CELL=$(escape_html "$CELL")
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
    title=$(escape_html "$title")
    echo "$title" > "$TEMP_DIR/title.txt"
    
    # Get max value for scaling
    local max_val=$(echo "$data" | jq '[.values[]] | max')
    local count=$(echo "$data" | jq '.labels | length')
    
    BARS_HTML=""
    for ((i=0; i<count; i++)); do
        local label=$(echo "$data" | jq -r ".labels[$i]")
        local value=$(echo "$data" | jq -r ".values[$i]")
        label=$(escape_html "$label")
        value=$(escape_html "$value")
        # Scale height to max 220px
        local height=$(echo "$value $max_val" | awk '{printf "%.0f", ($1/$2)*220}')
        BARS_HTML+="<div class=\"bar-wrapper\"><div class=\"bar\" style=\"height: ${height}px;\"><span class=\"bar-value\">$value</span></div><div class=\"bar-label\">$label</div></div>"
    done
    echo "$BARS_HTML" > "$TEMP_DIR/bars.html"
}

generate_stats() {
    local data="$1"
    
    # Extract title if present
    local title=$(echo "$data" | jq -r '.title // ""')
    if [[ -n "$title" && "$title" != "null" ]]; then
        title=$(escape_html "$title")
        echo "<div class=\"page-title\">$title</div>" > "$TEMP_DIR/title.html"
    else
        echo "" > "$TEMP_DIR/title.html"
    fi
    
    STATS_HTML=""
    STAT_COUNT=$(echo "$data" | jq '.stats | length')
    for ((i=0; i<STAT_COUNT; i++)); do
        LABEL=$(echo "$data" | jq -r ".stats[$i].label")
        VALUE=$(echo "$data" | jq -r ".stats[$i].value")
        CHANGE=$(echo "$data" | jq -r ".stats[$i].change // \"\"")
        
        # Escape all user-supplied text
        LABEL=$(escape_html "$LABEL")
        VALUE=$(escape_html "$VALUE")
        CHANGE=$(escape_html "$CHANGE")
        
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
    
    # Escape all user-supplied text
    TITLE=$(escape_html "$TITLE")
    SUBTITLE=$(escape_html "$SUBTITLE")
    BODY=$(escape_html "$BODY")
    
    IMAGE_HTML=""
    if [[ -n "$IMAGE" && "$IMAGE" != "null" ]]; then
        # Validate image URL (block dangerous protocols)
        IMAGE=$(validate_image_url "$IMAGE")
        if [[ -n "$IMAGE" ]]; then
            IMAGE=$(escape_html "$IMAGE")
            IMAGE_HTML="<img src=\"$IMAGE\" class=\"card-image\" />"
        fi
    fi
    
    STATUS_HTML=""
    if [[ -n "$STATUS" && "$STATUS" != "null" ]]; then
        # Only allow known status values
        case "$STATUS" in
            green|yellow|red)
                STATUS_HTML="<div class=\"card-status status-$STATUS\"></div>"
                ;;
        esac
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
    DASH_TITLE=$(escape_html "$DASH_TITLE")
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
                W_LABEL=$(escape_html "$W_LABEL")
                W_VALUE=$(escape_html "$W_VALUE")
                W_CHANGE=$(escape_html "$W_CHANGE")
                CHANGE_CLASS="neutral"
                [[ "$W_CHANGE" == +* ]] && CHANGE_CLASS="positive"
                [[ "$W_CHANGE" == -* ]] && CHANGE_CLASS="negative"
                WIDGETS_HTML+="<div class=\"widget widget-stat\"><div class=\"stat-label\">$W_LABEL</div><div class=\"stat-value\">$W_VALUE</div><div class=\"stat-change $CHANGE_CLASS\">$W_CHANGE</div></div>"
                ;;
            table)
                TH=""
                for col in $(echo "$WIDGET_DATA" | jq -r '.columns[]' 2>/dev/null); do
                    col=$(escape_html "$col")
                    TH+="<th>$col</th>"
                done
                TB=""
                W_ROW_COUNT=$(echo "$WIDGET_DATA" | jq '.rows | length' 2>/dev/null || echo 0)
                for ((r=0; r<W_ROW_COUNT; r++)); do
                    TB+="<tr>"
                    W_COL_COUNT=$(echo "$WIDGET_DATA" | jq ".rows[$r] | length")
                    for ((c=0; c<W_COL_COUNT; c++)); do
                        CELL=$(echo "$WIDGET_DATA" | jq -r ".rows[$r][$c]")
                        CELL=$(escape_html "$CELL")
                        TB+="<td>$CELL</td>"
                    done
                    TB+="</tr>"
                done
                WIDGETS_HTML+="<div class=\"widget widget-table\"><table><thead><tr>$TH</tr></thead><tbody>$TB</tbody></table></div>"
                ;;
            chart)
                # CSS-based bars (no JavaScript required)
                W_TITLE=$(echo "$WIDGET_DATA" | jq -r '.title // "Chart"')
                W_TITLE=$(escape_html "$W_TITLE")
                local w_count=$(echo "$WIDGET_DATA" | jq '.labels | length')
                local w_max=$(echo "$WIDGET_DATA" | jq '[.values[]] | max')
                BARS=""
                for ((b=0; b<w_count; b++)); do
                    local w_label=$(echo "$WIDGET_DATA" | jq -r ".labels[$b]")
                    local w_value=$(echo "$WIDGET_DATA" | jq -r ".values[$b]")
                    w_label=$(escape_html "$w_label")
                    w_value=$(escape_html "$w_value")
                    local w_height=$(echo "$w_value $w_max" | awk '{printf "%.0f", ($1/$2)*120}')
                    BARS+="<div style=\"display:inline-block;text-align:center;margin:0 8px;\"><div style=\"background:linear-gradient(180deg,#667eea,#764ba2);width:40px;height:${w_height}px;border-radius:4px 4px 0 0;\"></div><div style=\"font-size:11px;margin-top:4px;\">$w_label</div><div style=\"font-size:10px;color:#666;\">$w_value</div></div>"
                done
                WIDGETS_HTML+="<div class=\"widget widget-chart\"><div style=\"font-weight:600;margin-bottom:10px;\">$W_TITLE</div><div style=\"display:flex;align-items:flex-end;justify-content:center;height:150px;\">$BARS</div></div>"
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
            local title_html=$(cat "$TEMP_DIR/title.html")
            cat "$TEMPLATE_FILE" | \
                awk -v css="$theme_css" '{gsub(/\{\{THEME_CSS\}\}/, css); print}' | \
                awk -v th="$title_html" '{gsub(/\{\{TITLE_HTML\}\}/, th); print}' | \
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
            local title_html=$(cat "$TEMP_DIR/title.html")
            cat "$TEMPLATE_FILE" | \
                awk -v css="$theme_css" '{gsub(/\{\{THEME_CSS\}\}/, css); print}' | \
                awk -v th="$title_html" '{gsub(/\{\{TITLE_HTML\}\}/, th); print}' | \
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
