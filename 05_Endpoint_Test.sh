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

# Show tunnel connections
echo "🔗 Checking tunnel connections..."
if command -v cloudflared >/dev/null 2>&1; then
    # Check tunnel list
    echo "   📋 Available tunnels:"
    sudo cloudflared tunnel list 2>/dev/null | head -3 | sed 's/^/      /'
    
    # Check current tunnel status  
    echo "   🔍 Current tunnel status:"
    sudo systemctl status cloudflared --no-pager -l | grep -E "(Active|Main PID|Memory|CPU|CGroup)" | sed 's/^/      /'
    
    # Check recent logs for connection status
    echo "   📝 Recent tunnel logs (last 5 lines):"
    sudo journalctl -u cloudflared --no-pager -n 5 | sed 's/^/      /'
    
else
    warn "cloudflared command not found"
fi

# Wait for tunnel to be ready
echo "⏳ Waiting for tunnel connections to stabilize..."
sleep 5

# Extract endpoints from config and test them
ENDPOINTS_TESTED=0
ENDPOINTS_FAILED=0

echo "🔍 Extracting endpoints from config..."

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
        if [[ -n "$LOCAL_PORT" ]]; then
            echo "   🔍 Checking local service on port $LOCAL_PORT..."
            if netstat -tuln 2>/dev/null | grep -q ":$LOCAL_PORT "; then
                echo "   ✅ Local service is running on port $LOCAL_PORT"
            else
                echo "   ❌ Local service NOT running on port $LOCAL_PORT"
                echo "      💡 Try: sudo systemctl status jupyter-lab (for port 8888)"
                echo "      💡 Or check what's running: sudo ss -tlnp | grep $LOCAL_PORT"
            fi
        fi
        
        # Test DNS resolution
        echo "   🔍 Testing DNS resolution..."
        if nslookup "$HOSTNAME" >/dev/null 2>&1; then
            echo "   ✅ DNS resolution successful"
        else
            echo "   ❌ DNS resolution failed for $HOSTNAME"
            echo "      💡 Check tunnel status: sudo systemctl status cloudflared"
        fi
        
        # Test the endpoint with verbose error handling
        echo "   📞 Making HTTPS request with verbose output..."
        CURL_OUTPUT=$(mktemp)
        
        # First try to get just the HTTP code
        HTTP_CODE=$(curl -w "%{http_code}" -s -o /dev/null \
            --connect-timeout 10 --max-time 30 \
            "https://$HOSTNAME" 2>/dev/null || echo "000")
            
        # If that fails or returns weird code, try verbose mode
        if [[ "$HTTP_CODE" == "000" || "$HTTP_CODE" == "000000" ]]; then
            echo "   🔍 Connection issue detected, running verbose diagnostic..."
            
            # Try with verbose output and write info to temp file
            curl -v --connect-timeout 10 --max-time 30 \
                "https://$HOSTNAME" >"$CURL_OUTPUT" 2>&1
            CURL_EXIT_CODE=$?
            
            echo "   📊 Curl exit code: $CURL_EXIT_CODE"
            echo "   📊 Verbose curl output (last 10 lines):"
            tail -10 "$CURL_OUTPUT" | sed 's/^/      /'
            
            # Also try to extract actual HTTP status from verbose output
            VERBOSE_STATUS=$(grep -o "HTTP/[0-9.]\+ [0-9]\+" "$CURL_OUTPUT" | tail -1 | awk '{print $2}')
            if [[ -n "$VERBOSE_STATUS" ]]; then
                echo "   📊 HTTP status from verbose: $VERBOSE_STATUS"
                HTTP_CODE="$VERBOSE_STATUS"
            fi
        else
            CURL_EXIT_CODE=0
            echo "   📊 Curl exit code: $CURL_EXIT_CODE"
            echo "   📊 HTTP response code: $HTTP_CODE"
        fi
        
        rm -f "$CURL_OUTPUT"
        
        case "$HTTP_CODE" in
            200|302)
                ok "$HOSTNAME - Response: HTTP $HTTP_CODE"
                ;;
            000)
                fail "$HOSTNAME - Connection failed"
                case $CURL_EXIT_CODE in
                    6) echo "      💡 Could not resolve host - tunnel may not be running" ;;
                    7) echo "      💡 Failed to connect - check tunnel service status" ;;
                    28) echo "      💡 Operation timeout - service may be slow" ;;
                    35) echo "      💡 SSL connect error - certificate issues" ;;
                    *) echo "      💡 Curl error code $CURL_EXIT_CODE - check connectivity" ;;
                esac
                echo "      🔧 Debug steps:"
                echo "         sudo systemctl status cloudflared"
                echo "         sudo journalctl -u cloudflared -f"
                ENDPOINTS_FAILED=$((ENDPOINTS_FAILED + 1))
                ;;
            *)
                warn "$HOSTNAME - Response: HTTP $HTTP_CODE (may need investigation)"
                echo "      💡 Non-standard response - check application logs"
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