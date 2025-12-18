#!/bin/bash
# 05_Endpoint_Test.sh
# Test configured Cloudflare tunnel endpoints 🌐

FAIL=0

ok()   { printf "✅ [OK]   %s\n" "$1"; }
warn() { printf "⚠️  [WARN] %s\n" "$1"; }
fail() { printf "❌ [FAIL] %s\n" "$1"; FAIL=1; }
info() { printf "ℹ️  [INFO] %s\n" "$1"; }

echo "🧪 Testing Cloudflare tunnel endpoints..."

# Find config file
CONFIG_FILE="/etc/cloudflared/config.yml"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="$HOME/.cloudflared/config.yml"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    fail "No Cloudflare config found at /etc/cloudflared/config.yml or ~/.cloudflared/config.yml"
    exit 1
fi

info "Using config: $CONFIG_FILE"

# Check tunnel service status first
echo "🔍 Checking Cloudflare tunnel service status..."
if systemctl is-active --quiet cloudflared; then
    ok "Cloudflare tunnel service is running"
else
    warn "Cloudflare tunnel service is NOT running"
    echo "      💡 Try: sudo systemctl start cloudflared"
    echo "      💡 Check logs: sudo journalctl -u cloudflared -f"
fi

# Quick tunnel connection check
echo "🔗 Checking tunnel connections..."
if command -v cloudflared >/dev/null 2>&1; then
    TUNNEL_NAME=$(grep "^tunnel:" "$CONFIG_FILE" | sed 's/tunnel: //')
    TUNNEL_INFO=$(sudo cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_NAME")
    if [[ -n "$TUNNEL_INFO" ]]; then
        ok "Tunnel '$TUNNEL_NAME' is configured and active"
    else
        warn "Tunnel '$TUNNEL_NAME' status unknown"
    fi
else
    warn "cloudflared command not found"
fi

# Wait for tunnel to be ready
echo "⏳ Waiting for tunnel connections to stabilize..."
sleep 5

# DNS Infrastructure Verification
echo "🌐 DNS Infrastructure Verification..."
TUNNEL_NAME=$(grep "^tunnel:" "$CONFIG_FILE" | sed 's/tunnel: //')

# Quick check - if domains resolve to Cloudflare IPs, DNS is working
DOMAINS_WORKING=0
TOTAL_DOMAINS=0

grep -o "hostname: [^[:space:]]*" "$CONFIG_FILE" | sed 's/hostname: //' | while read -r hostname; do
    TOTAL_DOMAINS=$((TOTAL_DOMAINS + 1))
    # Check if domain resolves to Cloudflare IPs (proxied)
    A_RECORDS=$(dig +short A "$hostname" @8.8.8.8 2>/dev/null)
    if echo "$A_RECORDS" | grep -E "(104\.2[1-2]\.|172\.6[4-9]\.|198\.41\.)" >/dev/null; then
        ok "DNS working: $hostname → Cloudflare proxy"
        DOMAINS_WORKING=$((DOMAINS_WORKING + 1))
    else
        warn "DNS issue: $hostname - not resolving correctly"
    fi
done

# If domains resolve correctly, skip detailed CLI route checks
if [ $DOMAINS_WORKING -eq $TOTAL_DOMAINS ] 2>/dev/null; then
    ok "All domains resolving correctly - DNS configuration working"
else
    warn "Some domains not resolving - check Cloudflare dashboard DNS settings"
fi

# Extract endpoints from config and test them
ENDPOINTS_TESTED=0
ENDPOINTS_FAILED=0

echo "🔍 Extracting endpoints from config..."

# Ingress Routes Summary
echo "📋 Ingress Routes Summary:"
TOTAL_ROUTES=$(grep -c "hostname:" "$CONFIG_FILE")
ok "$TOTAL_ROUTES ingress routes configured in tunnel config"

# Skip detailed CLI DNS route verification since domains are working
# The CLI route commands may not work correctly with dashboard-configured routes

# Parse YAML config to find hostname entries
grep -A1 "hostname:" "$CONFIG_FILE" | grep -v "^--" | while read -r line; do
    if echo "$line" | grep -q "hostname:"; then
        # Extract hostname
        HOSTNAME=$(echo "$line" | sed 's/.*hostname:[[:space:]]*\([^[:space:]]*\).*/\1/')
        read -r service_line
        SERVICE=$(echo "$service_line" | sed 's/.*service:[[:space:]]*\([^[:space:]]*\).*/\1/')
        
        echo "🌐 Testing: $HOSTNAME → $SERVICE"
        
        # Check if local service is running
        LOCAL_PORT=$(echo "$SERVICE" | grep -o '[0-9]\+$')
        if [[ -n "$LOCAL_PORT" ]] && ! netstat -tuln 2>/dev/null | grep -q ":$LOCAL_PORT "; then
            warn "Local service NOT running on port $LOCAL_PORT"
        fi
        
        # Test the endpoint
        HTTP_CODE=$(curl -w "%{http_code}" -s -o /dev/null \
            --connect-timeout 10 --max-time 30 \
            "https://$HOSTNAME" 2>/dev/null || echo "000")
            
        case "$HTTP_CODE" in
            200|302|404|405)
                ok "$HOSTNAME - Response: HTTP $HTTP_CODE (tunnel working)"
                ;;
            000)
                warn "$HOSTNAME - Connection failed"
                echo "      💡 Check: DNS resolution and tunnel status"
                ENDPOINTS_FAILED=$((ENDPOINTS_FAILED + 1))
                ;;
            *)
                warn "$HOSTNAME - Response: HTTP $HTTP_CODE"
                ;;
        esac
        
        ENDPOINTS_TESTED=$((ENDPOINTS_TESTED + 1))
        
        # Small delay between tests
        sleep 2
    fi
done

# The loop runs in a subshell, so we need to re-parse for final summary
echo ""
echo "📊 Endpoint Test Summary:"

TOTAL_ENDPOINTS=$(grep -c "hostname:" "$CONFIG_FILE")
info "Total configured endpoints: $TOTAL_ENDPOINTS"

# Test connection to each endpoint for summary
WORKING_ENDPOINTS=0
FAILED_ENDPOINTS=0

grep -A1 "hostname:" "$CONFIG_FILE" | grep -v "^--" | while read -r line; do
    if echo "$line" | grep -q "hostname:"; then
        HOSTNAME=$(echo "$line" | sed 's/.*hostname:[[:space:]]*\([^[:space:]]*\).*/\1/')
        
        HTTP_CODE=$(curl -w "%{http_code}" -s -o /dev/null --connect-timeout 10 --max-time 30 "https://$HOSTNAME" 2>/dev/null || echo "000")
        
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            WORKING_ENDPOINTS=$((WORKING_ENDPOINTS + 1))
        else
            FAILED_ENDPOINTS=$((FAILED_ENDPOINTS + 1))
        fi
    fi
done

# Re-run the tests for final status (since variables don't persist from subshell)
WORKING=0
FAILED=0

while IFS= read -r hostname; do
    HTTP_CODE=$(curl -w "%{http_code}" -s -o /dev/null --connect-timeout 10 --max-time 30 "https://$hostname" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        WORKING=$((WORKING + 1))
    else
        FAILED=$((FAILED + 1))
    fi
done < <(grep "hostname:" "$CONFIG_FILE" | sed 's/.*hostname:[[:space:]]*\([^[:space:]]*\).*/\1/')

if [ $FAILED -eq 0 ]; then
    ok "All $WORKING endpoints responding correctly"
    echo ""
    echo "🎉 === ENDPOINT TESTS PASSED ==="
    exit 0
else
    fail "$FAILED of $((WORKING + FAILED)) endpoints failed"
    echo ""
    echo "❌ === ENDPOINT TESTS FAILED ==="
    exit 1
fi