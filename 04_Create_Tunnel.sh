#!/bin/bash
# 04_Create_Tunnel.sh
# Create Cloudflare tunnel to nginx with domain routing 🌐

FAIL=0

ok()   { printf "✅ [OK]   %s\n" "$1"; }
warn() { printf "⚠️  [WARN] %s\n" "$1"; }
fail() { printf "❌ [FAIL] %s\n" "$1"; FAIL=1; }
info() { printf "ℹ️  [INFO] %s\n" "$1"; }

# Handle status mode
if [ "$1" = "status" ]; then
    echo "📊 Cloudflare Tunnel Status:"
    
    # Check if running as system service
    if systemctl is-active --quiet cloudflared 2>/dev/null; then
        ok "Cloudflare tunnel service running"
        SERVICE_STATUS=$(systemctl show cloudflared --property=ActiveState --value)
        ok "Service status: $SERVICE_STATUS"
        
        # Show service info
        SINCE=$(systemctl show cloudflared --property=ActiveEnterTimestamp --value)
        ok "Running since: $SINCE"
        
    # Check for manual processes
    elif pgrep cloudflared > /dev/null; then
        warn "Cloudflare tunnel running manually (not as service)"
    else
        warn "Cloudflare tunnel not running"
        echo "💡 Start with: sudo systemctl start cloudflared"
    fi
    
    # Show configured tunnels
    CONFIG_FILE="/etc/cloudflared/config.yml"
    if [ ! -f "$CONFIG_FILE" ]; then
        CONFIG_FILE="$HOME/.cloudflared/config.yml"
    fi
    
    if [ -f "$CONFIG_FILE" ]; then
        info "Active tunnel configuration: $CONFIG_FILE"
        echo "📋 Configured domains:"
        grep -E "hostname.*tb-cloudlab" "$CONFIG_FILE" | while read -r line; do
            DOMAIN=$(echo "$line" | sed 's/.*hostname:[[:space:]]*\([^[:space:]]*\).*/\1/')
            SERVICE=$(grep -A1 "hostname.*$DOMAIN" "$CONFIG_FILE" | grep "service:" | sed 's/.*service:[[:space:]]*\([^[:space:]]*\).*/\1/')
            echo "   • $DOMAIN → $SERVICE"
        done
    else
        warn "No tunnel configuration found"
    fi
    exit 0
fi

echo "🌐 Setting up Cloudflare tunnel with direct port routing..."

# Check if cloudflared is installed
if ! command -v cloudflared >/dev/null 2>&1; then
    fail "cloudflared not installed. Install with: curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared && sudo install cloudflared /usr/local/bin/"
    exit 1
fi

# Check for system service first
if systemctl list-unit-files | grep -q cloudflared; then
    echo "📋 System service detected - using systemd management"
    
    if systemctl is-active --quiet cloudflared; then
        ok "Cloudflare tunnel already running as service"
        echo "🔄 Restarting service to apply any config changes..."
        sudo systemctl restart cloudflared
    else
        echo "🚀 Starting Cloudflare tunnel service..."
        sudo systemctl start cloudflared
    fi
    
    # Wait for service to be active
    sleep 3
    if systemctl is-active --quiet cloudflared; then
        ok "Cloudflare tunnel service active"
        echo "📋 Configured domains:"
        echo "   • jupyter.tb-cloudlab.cloudflareaccess.com → localhost:8888"
        echo "   • web.tb-cloudlab.cloudflareaccess.com → localhost:8000"
        echo ""
        echo "🔧 Service management:"
        echo "   • Status: sudo systemctl status cloudflared"
        echo "   • Stop: sudo systemctl stop cloudflared"
        echo "   • Logs: sudo journalctl -u cloudflared -f"
        echo ""
        echo "🎉 === CLOUDFLARE TUNNEL SERVICE ACTIVE ==="
        exit 0
    else
        fail "Failed to start cloudflared service"
        echo "🔍 Check logs: sudo journalctl -u cloudflared -n 20"
        exit 1
    fi
fi

# Fallback to manual mode if no service
echo "📋 No system service - using manual mode"

# Check if tunnel config exists
if [ ! -f ~/.cloudflared/config.yml ]; then
    fail "No Cloudflare tunnel config found. Please run 'cloudflared tunnel login' and configure your tunnel first"
    echo "See: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/"
    exit 1
fi

echo "🔧 Using tunnel configuration from ~/.cloudflared/config.yml"

# Clean up any existing cloudflared processes
echo "🧹 Cleaning up existing cloudflared processes..."
pkill cloudflared 2>/dev/null || true
sleep 2

echo "🚀 Starting Cloudflare tunnel..."
# Start cloudflared as background service
cloudflared tunnel --config ~/.cloudflared/config.yml run &
sleep 3

echo "⏳ Waiting for tunnel to establish connection..."
for i in $(seq 1 15); do
    if pgrep cloudflared > /dev/null; then
        ok "Cloudflare tunnel process running"
        echo "🌐 Tunnel Active - Check Cloudflare Dashboard for connection status"
        echo "🛑 Stop tunnel: make clean"
        echo ""
        echo "🎉 === CLOUDFLARE TUNNEL READY ==="
        exit 0
    fi
    
    echo "   ...still waiting ($i/15)"
    sleep 2
done

fail "Cloudflare tunnel failed to start"
echo "🔍 Check logs: cloudflared tunnel --config ~/.cloudflared/config.yml run"
exit 1