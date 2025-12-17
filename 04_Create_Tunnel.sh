#!/bin/bash
# 04_Create_Tunnel.sh
# Create ngrok tunnel to nginx with HTTPS and basic authentication 🚇

FAIL=0

ok()   { printf "✅ [OK]   %s\n" "$1"; }
warn() { printf "⚠️  [WARN] %s\n" "$1"; }
fail() { printf "❌ [FAIL] %s\n" "$1"; FAIL=1; }
info() { printf "ℹ️  [INFO] %s\n" "$1"; }

# Handle status mode
if [ "$1" = "status" ]; then
    echo "📊 Ngrok Tunnel Status:"
    if pgrep ngrok > /dev/null; then
        url=$(curl -s --max-time 2 http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -o 'https://[^"]*' | head -n 1 || true)
        if [ -n "$url" ]; then
            ok "HTTPS tunnel active: $url"
        else
            info "ngrok running, check: http://localhost:4040"
        fi
    else
        warn "ngrok not running - run 'make serve' to start"
    fi
    exit 0
fi

echo "🚇 Creating ngrok tunnel to nginx with HTTPS and basic auth..."

# Check if ngrok config exists
if [ ! -f ~/.config/ngrok/ngrok.yml ]; then
    fail "No ngrok config found. Please run 'ngrok config add-authtoken <YOUR_TOKEN>' first"
    echo "Get your token from: https://dashboard.ngrok.com/get-started/your-authtoken"
    exit 1
fi

echo "🔧 Using configurations from ~/.config/ngrok/ (ngrok-server.yml and traffic-policy.yml)"

# Clean up any existing ngrok processes
echo "🧹 Cleaning up existing ngrok processes..."
pkill ngrok 2>/dev/null || true
sleep 2

echo "🚀 Starting ngrok tunnel in background..."
# Start ngrok completely detached from terminal
setsid nohup ngrok start --config ~/.config/ngrok/ngrok.yml --config ~/.config/ngrok/ngrok-server.yml --all </dev/null >ngrok.log 2>&1 &
sleep 3

echo "⏳ Waiting for ngrok API to become available..."
for i in $(seq 1 15); do
    url=$(curl -s --max-time 2 http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -o 'https://[^"]*' | head -n 1 || true)
    if [ -n "$url" ]; then
        ok "ngrok tunnel established: $url"
        echo "🔐 Basic Authentication Required!"
        echo "📊 Web Interface: http://localhost:4040"
        echo "🛑 Stop tunnel: make clean"
        echo ""
        echo "🎉 === TUNNEL READY ==="
        exit 0
    fi
    
    echo "   ...still waiting ($i/15)"
    if [ $((i % 5)) -eq 0 ]; then
        echo "🔍 Partial ngrok log:"
        tail -n 5 ngrok.log 2>/dev/null || true
    fi
    sleep 2
done

# Timeout reached
fail "ngrok tunnel failed to start within timeout"
echo ""
echo "🧾 Full ngrok log output for debugging:"
cat ngrok.log 2>/dev/null || true
echo ""
echo "🔥 === TUNNEL CREATION FAILED ==="
exit 1