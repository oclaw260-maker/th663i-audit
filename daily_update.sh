#!/usr/bin/env bash
# Daily update pipeline:
#   1. Drain new Event Hub data (continues from prior _progress.txt)
#   2. Extract profiles + raw samples
#   3. Rebuild dashboard HTML
#   4. Deploy to GitHub Pages
#
# Logs to ~/.hermes/cron/output/th663-daily-update.log

set -e
LOGFILE="$HOME/.hermes/cron/output/th663-daily-update.log"
mkdir -p "$(dirname "$LOGFILE")"
echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) ===" >> "$LOGFILE"

# Use hermes venv for python (has azure-eventhub installed)
PY=/home/turbo/.hermes/hermes-agent/venv/bin/python3
SITE=/home/turbo/th663-audit-site

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOGFILE" ; }

log "Step 1: Drain any new Event Hub data"
cd /home/turbo
"$PY" drain_th663.py >> "$LOGFILE" 2>&1 || log "drain exit $? (non-fatal, continuing)"

log "Step 2: Extract profiles + raw samples"
"$PY" extract_th663_hub.py >> "$LOGFILE" 2>&1 || { log "extract failed"; exit 1; }
"$PY" export_raw_samples.py >> "$LOGFILE" 2>&1 || { log "raw-sample export failed"; exit 1; }

log "Step 3: Rebuild dashboard HTMLs"
"$PY" build_hub_dashboard.py >> "$LOGFILE" 2>&1 || { log "dashboard build failed"; exit 1; }
"$PY" build_echarts_dashboard.py >> "$LOGFILE" 2>&1 || { log "echarts dashboard build failed"; exit 1; }

log "Step 4: Stage + deploy"
cp /home/turbo/th663_hub_audit.html "$SITE/index.html"
cp /home/turbo/th663_hub_audit_echarts.html "$SITE/echarts.html"

cd "$SITE"
# Skip deploy if no changes detected (either file)
changed=0
for f in index.html echarts.html; do
  if git diff --quiet -- "$f" 2>/dev/null; then
    :
  else
    changed=1
    break
  fi
done
if [ "$changed" -eq 0 ]; then
  log "No content change vs last deploy — skipping push"
  echo "" >> "$LOGFILE"
  exit 0
fi

"$PY" deploy.py >> "$LOGFILE" 2>&1 || { log "deploy failed"; exit 1; }

# Pages build lag — poll up to 90s for the new build to be live
URL="https://oclaw260-maker.github.io/th663i-audit/"
log "Polling $URL for the fresh build"
for i in $(seq 1 18); do
  SIZE=$(curl -s --max-time 6 "$URL" 2>/dev/null | wc -c)
  if [ "$SIZE" -gt 1000000 ]; then
    log "Build live: $SIZE bytes on check $i"
    break
  fi
  sleep 5
done

# Confirm key marker from THIS run on index.html
PAGE=$(curl -s --max-time 6 "$URL")
if echo "$PAGE" | grep -q 'baseline (empty):'; then
  log "Verified: new bar-chart marker present on index.html"
else
  log "WARN: new bar-chart marker not visible yet on index.html — Pages may still be propagating"
fi

# Confirm ECharts page is also live
ECHARTS_URL="${URL}echarts.html"
ECHARTS_SIZE=$(curl -s --max-time 6 "$ECHARTS_URL" 2>/dev/null | wc -c)
if [ "$ECHARTS_SIZE" -gt 1000000 ]; then
  log "ECharts page live: $ECHARTS_SIZE bytes"
else
  log "WARN: ECharts page not yet live at $ECHARTS_URL"
fi

log "Daily update complete"
echo "" >> "$LOGFILE"
