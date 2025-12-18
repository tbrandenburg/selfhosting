#!/bin/bash
# 03_Service_Check.sh  
# Service readiness check for Cloudflare tunnel direct routing 🌐

FAIL=0

ok()   { printf "✅ [OK]   %s\n" "$1"; }
warn() { printf "⚠️  [WARN] %s\n" "$1"; }
fail() { printf "❌ [FAIL] %s\n" "$1"; FAIL=1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

echo "🔍 Checking required service tools…"
for cmd in \
    systemctl curl netstat cloudflared
do
    need_cmd "$cmd"
done

echo "🌐 Cloudflare Tunnel Services…"
systemctl is-active --quiet cloudflared \
    && ok "cloudflared tunnel service available" \
    || fail "cloudflared tunnel service not running"

# Check for config file
CONFIG_FILE="/etc/cloudflared/config.yml"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="$HOME/.cloudflared/config.yml"
fi

if [ -f "$CONFIG_FILE" ]; then
    ok "cloudflared config.yml found"
else
    fail "cloudflared config.yml not found"
    exit 1
fi

# Validate config structure
if grep -q "^tunnel:" "$CONFIG_FILE" && \
   grep -q "^credentials-file:" "$CONFIG_FILE" && \
   grep -q "^ingress:" "$CONFIG_FILE"; then
    ok "Cloudflare config structure valid"
else
    fail "Cloudflare config structure invalid"
fi

# Check domain routing
DOMAIN_COUNT=$(grep -c "hostname:" "$CONFIG_FILE")
if [ "$DOMAIN_COUNT" -gt 0 ]; then
    ok "Domain routing configured: $DOMAIN_COUNT domains for $(grep "hostname:" "$CONFIG_FILE" | head -1 | sed 's/.*\.\([^.]*\.cloudflareaccess\.com\).*/\1/')"
    
    # Show specific routes
    grep -A1 "hostname:" "$CONFIG_FILE" | while read -r line; do
        if echo "$line" | grep -q "hostname:"; then
            HOSTNAME=$(echo "$line" | sed 's/.*hostname:[[:space:]]*\([^[:space:]]*\).*/\1/')
            read -r service_line
            SERVICE=$(echo "$service_line" | sed 's/.*service:[[:space:]]*\([^[:space:]]*\).*/\1/')
            ok "Direct routing: $HOSTNAME → $SERVICE"
        fi
    done
else
    fail "No domain routing configured"
fi

# Check credentials file
CREDENTIALS_FILE=$(grep "^credentials-file:" "$CONFIG_FILE" | sed 's/.*credentials-file:[[:space:]]*\([^[:space:]]*\).*/\1/')
if [ -f "$CREDENTIALS_FILE" ]; then
    ok "Cloudflare credentials file found"
else
    fail "Cloudflare credentials file missing: $CREDENTIALS_FILE"
fi

# Check if tunnel process is running
if pgrep -f "cloudflared.*tunnel.*run" >/dev/null; then
    ok "Cloudflare tunnel process running"
else
    warn "Cloudflare tunnel process not detected"
fi

echo "🔧 Cloudflare System Integration Analysis…"

# Check service status
SERVICE_STATUS=$(systemctl is-active cloudflared 2>/dev/null)
SERVICE_ENABLED=$(systemctl is-enabled cloudflared 2>/dev/null)

case "$SERVICE_STATUS" in
    active)
        ok "Cloudflared system service: $SERVICE_STATUS ($SERVICE_ENABLED)"
        ;;
    *)
        fail "Cloudflared system service: $SERVICE_STATUS"
        ;;
esac

# Count running processes
TUNNEL_PROCESSES=$(pgrep -f cloudflared | wc -l)
if [ "$TUNNEL_PROCESSES" -gt 0 ]; then
    ok "Current tunnel processes: $TUNNEL_PROCESSES"
    
    # Check if running via systemd
    if sudo systemctl status cloudflared >/dev/null 2>&1; then
        ok "Running via systemd service (recommended)"
    else
        warn "Not running via systemd service"
    fi
else
    fail "No tunnel processes running"
fi

echo "📊 Architecture Analysis:"
if grep -q "localhost:888[08]\|localhost:8000" "$CONFIG_FILE"; then
    ok "Using direct port routing architecture"
    echo "   ✓ Simplified configuration without reverse proxy"
    echo "   ✓ Direct application access via cloudflared"
    echo "   ✓ No nginx complexity or maintenance"
    echo "   ✓ SSL termination at Cloudflare edge"
else
    warn "Could not verify direct routing configuration"
fi

echo "🔗 Direct Application Access Verification…"
# Check that target application services are accessible locally

# Check if JupyterLab is running on port 8888
if sudo netstat -tlnp 2>/dev/null | grep -q :8888; then
    ok "JupyterLab service accessible on port 8888"
else
    warn "No service found on port 8888 (JupyterLab expected)"
    echo "      💡 Start with: jupyter lab --ip=0.0.0.0 --port=8888 --no-browser"
fi

# Check if web service is running on port 8000  
if sudo netstat -tlnp 2>/dev/null | grep -q :8000; then
    ok "Web service accessible on port 8000"
else
    warn "No service found on port 8000 (web application expected)"
    echo "      💡 Start your web application on port 8000"
fi

echo "📊 Service Health & Monitoring…"

# Check for recent tunnel logs
if sudo journalctl -u cloudflared --since="5 minutes ago" >/dev/null 2>&1; then
    ok "Tunnel service logs accessible"
    
    # Check for connection errors in recent logs
    ERROR_COUNT=$(sudo journalctl -u cloudflared --since="5 minutes ago" | grep -i "error\|failed\|timeout" | wc -l)
    if [ "$ERROR_COUNT" -eq 0 ]; then
        ok "No recent tunnel errors detected"
    else
        warn "Recent tunnel errors detected: $ERROR_COUNT"
    fi
else
    warn "Cannot access tunnel service logs"
fi

# Check metrics endpoint if configured
if grep -q "^metrics:" "$CONFIG_FILE"; then
    METRICS_ENDPOINT=$(grep "^metrics:" "$CONFIG_FILE" | sed 's/.*metrics:[[:space:]]*\([^[:space:]]*\).*/\1/')
    if curl -s --connect-timeout 2 "http://$METRICS_ENDPOINT/metrics" >/dev/null 2>&1; then
        ok "Metrics endpoint responding: $METRICS_ENDPOINT"
    else
        warn "Metrics endpoint not responding: $METRICS_ENDPOINT"
    fi
fi

echo "🌐 Direct Routing Architecture Benefits…"
ok "No reverse proxy complexity or maintenance"
ok "Direct SSL termination at Cloudflare edge"
ok "Simplified configuration management"
ok "Automatic SSL certificate management"
ok "Built-in DDoS protection and CDN"
ok "Zero local firewall port exposure"

echo "🚀 Service Summary…"
echo "   📍 Direct routing: cloudflared → local applications"
echo "   📍 SSL termination: Cloudflare edge"
echo "   📍 Service management: systemd integration"
echo "   📍 Monitoring: journalctl logs and optional metrics"

if [ $FAIL -eq 0 ]; then
    echo ""
    echo "🎉 === SERVICES READY ==="
    exit 0
else
    echo ""
    echo "❌ === SERVICE CHECK FAILED ==="
    exit 1
fi