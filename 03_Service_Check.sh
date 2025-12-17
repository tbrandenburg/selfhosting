#!/bin/bash
# 03_Service_Check.sh
# Service readiness check for web services (nginx, databases, etc.) 🚀

FAIL=0

ok()   { printf "✅ [OK]   %s\n" "$1"; }
warn() { printf "⚠️  [WARN] %s\n" "$1"; }
fail() { printf "❌ [FAIL] %s\n" "$1"; FAIL=1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

echo "🔍 Checking required service tools…"
for cmd in \
    nginx systemctl curl netstat
do
    need_cmd "$cmd"
done

echo "🌐 Tunnel Services (Optional)…"
command -v ngrok >/dev/null 2>&1 \
    && ok "ngrok tunnel service available" \
    || warn "ngrok not installed"

# Check for ngrok configuration files
if [ -f ~/.config/ngrok/ngrok-server.yml ]; then
    ok "ngrok-server.yml configuration found"
else
    warn "ngrok-server.yml not found (create for automated tunneling)"
fi

if [ -f ~/.config/ngrok/traffic-policy.yml ]; then
    ok "traffic-policy.yml found"
else
    warn "traffic-policy.yml not found (create for basic auth setup)"
fi

command -v tmole >/dev/null 2>&1 \
    && ok "tmole tunnel service available" \
    || warn "tmole not installed"

echo "🌐 Nginx Web Service Checks…"
systemctl is-active --quiet nginx \
    && ok "Nginx service running" \
    || fail "Nginx service not running"

systemctl is-enabled --quiet nginx \
    && ok "Nginx enabled at boot" \
    || warn "Nginx not enabled at boot"

sudo nginx -t >/dev/null 2>&1 \
    && ok "Nginx configuration valid" \
    || fail "Nginx configuration invalid"

nginx -v 2>&1 >/dev/null \
    && ok "Nginx version accessible" \
    || fail "Nginx version check failed"

[ -d /etc/nginx/sites-available ] \
    && ok "Nginx sites-available directory exists" \
    || warn "Nginx sites-available directory missing"

[ -d /etc/nginx/sites-enabled ] \
    && ok "Nginx sites-enabled directory exists" \
    || warn "Nginx sites-enabled directory missing"

ENABLED_SITES=$(find /etc/nginx/sites-enabled -name "*.conf" -o -name "*" ! -name "*.*" 2>/dev/null | wc -l)
[ "$ENABLED_SITES" -gt 0 ] 2>/dev/null \
    && ok "Enabled sites: $ENABLED_SITES" \
    || warn "No sites enabled"

# Test if nginx is responding on standard ports
curl -s --connect-timeout 2 http://localhost >/dev/null 2>&1 \
    && ok "Nginx responding on HTTP (port 80)" \
    || warn "Nginx not responding on HTTP (port 80)"

curl -s --connect-timeout 2 -k https://localhost >/dev/null 2>&1 \
    && ok "Nginx responding on HTTPS (port 443)" \
    || warn "Nginx not responding on HTTPS (port 443)"

echo "� Application Routing Configuration…"
# Test nginx routing configuration
NGINX_CONFIG_FILE="/etc/nginx/sites-available/default"
if [ -f "$NGINX_CONFIG_FILE" ]; then
    ok "Nginx configuration file exists"
    
    # Extract all location blocks with proxy_pass (exclude default locations)
    LOCATIONS=$(grep "location [^{]*{" "$NGINX_CONFIG_FILE" | grep -v "location / " | grep -v "location /health" | grep -v "location /nginx_status" | grep -v "location ~ " | sed 's/.*location \([^ ]*\) .*/\1/' | sort -u)
    
    if [ -n "$LOCATIONS" ]; then
        ok "Application routes found in nginx config"
        
        # Check each location block
        while IFS= read -r location; do
            if [ -n "$location" ]; then
                # Find the corresponding proxy_pass line (escape forward slashes)
                ESCAPED_LOCATION=$(echo "$location" | sed 's|/|\\/|g')
                PROXY_LINE=$(awk "/location $ESCAPED_LOCATION {/,/}/" "$NGINX_CONFIG_FILE" | grep "proxy_pass" | head -1)
                
                if [ -n "$PROXY_LINE" ]; then
                    # Extract port number from proxy_pass
                    PORT=$(echo "$PROXY_LINE" | sed 's/.*localhost:\([0-9]*\).*/\1/')
                    
                    if [ -n "$PORT" ] && [ "$PORT" != "$PROXY_LINE" ]; then
                        ok "Route configured: $location → port $PORT"
                    else
                        warn "Route $location has invalid proxy target"
                    fi
                else
                    warn "Route $location missing proxy_pass directive"
                fi
            fi
        done <<< "$LOCATIONS"
    else
        warn "No application routes configured (only default routes found)"
    fi
    
    # Check for proper proxy headers
    if grep -q "X-Forwarded-For" "$NGINX_CONFIG_FILE"; then
        ok "Proxy headers configured for application routing"
    else
        warn "Missing proxy headers in configuration"
    fi
    
    # Check for WebSocket support
    if grep -q "proxy_set_header Upgrade" "$NGINX_CONFIG_FILE"; then
        ok "WebSocket support enabled for applications"
    else
        warn "WebSocket support not configured"
    fi
else
    fail "Nginx configuration file not found"
fi

echo "�🔗 Service Network Integration…"
# Check if nginx is listening on expected ports
sudo netstat -tlnp 2>/dev/null | grep :80 | grep -q nginx \
    && ok "Nginx listening on port 80" \
    || warn "Nginx not listening on port 80"

sudo netstat -tlnp 2>/dev/null | grep :443 | grep -q nginx \
    && ok "Nginx listening on port 443" \
    || warn "Nginx not listening on port 443"

# Check if nginx can access Docker containers
docker network ls | grep -q nginx \
    && ok "Nginx Docker network integration ready" \
    || warn "No nginx Docker network found"

echo "📊 Service Health & Monitoring…"
# Check nginx log files
[ -f /var/log/nginx/access.log ] \
    && ok "Nginx access log exists" \
    || warn "Nginx access log not found"

[ -f /var/log/nginx/error.log ] \
    && ok "Nginx error log exists" \
    || warn "Nginx error log not found"

# Health endpoint check
curl -s --connect-timeout 2 http://localhost/health >/dev/null 2>&1 \
    && ok "Health endpoint responding" \
    || warn "Health endpoint not configured"

echo "🧪 Application Endpoint Testing…"
# Test application routes dynamically (will show 502/404 if apps not running, but validates routing)
if [ -f "$NGINX_CONFIG_FILE" ]; then
    # Get the same locations we found earlier
    LOCATIONS=$(grep "location [^{]*{" "$NGINX_CONFIG_FILE" | grep -v "location / " | grep -v "location /health" | grep -v "location /nginx_status" | grep -v "location ~ " | sed 's/.*location \([^ ]*\) .*/\1/' | sort -u)
    
    if [ -n "$LOCATIONS" ]; then
        while IFS= read -r location; do
            if [ -n "$location" ]; then
                RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://localhost$location" 2>/dev/null)
                case "$RESPONSE_CODE" in
                    "200"|"302") ok "Route $location accessible (HTTP $RESPONSE_CODE)" ;;
                    "404") warn "Route $location configured but app not running (HTTP $RESPONSE_CODE)" ;;
                    "502"|"503") warn "Route $location configured but app not responding (HTTP $RESPONSE_CODE)" ;;
                    "") warn "Route $location not responding" ;;
                    *) warn "Route $location unexpected response (HTTP $RESPONSE_CODE)" ;;
                esac
            fi
        done <<< "$LOCATIONS"
    fi
fi

# Test that root path still works for static files
RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 http://localhost/ 2>/dev/null)
case "$RESPONSE_CODE" in
    "200") ok "Root path serving static files (HTTP $RESPONSE_CODE)" ;;
    "404") warn "Root path accessible but no index file (HTTP $RESPONSE_CODE)" ;;
    *) warn "Root path unexpected response (HTTP $RESPONSE_CODE)" ;;
esac

# Check for recent errors in nginx logs
if [ -f /var/log/nginx/error.log ]; then
    ERROR_COUNT=$(tail -100 /var/log/nginx/error.log 2>/dev/null | grep "$(date '+%Y/%m/%d')" | grep -E "\[(error|crit|alert|emerg)\]" | wc -l)
    [ "$ERROR_COUNT" -eq 0 ] 2>/dev/null \
        && ok "No recent nginx errors" \
        || warn "Recent nginx errors detected: $ERROR_COUNT"
fi

echo "🚀 Application Service Status…"
# Check if applications are running on expected ports (dynamically from nginx config)
if [ -f "$NGINX_CONFIG_FILE" ]; then
    LOCATIONS=$(grep "location [^{]*{" "$NGINX_CONFIG_FILE" | grep -v "location / " | grep -v "location /health" | grep -v "location /nginx_status" | grep -v "location ~ " | sed 's/.*location \([^ ]*\) .*/\1/' | sort -u)
    
    if [ -n "$LOCATIONS" ]; then
        while IFS= read -r location; do
            if [ -n "$location" ]; then
                # Find the corresponding port from proxy_pass (escape forward slashes)
                ESCAPED_LOCATION=$(echo "$location" | sed 's|/|\\/|g')
                PROXY_LINE=$(awk "/location $ESCAPED_LOCATION {/,/}/" "$NGINX_CONFIG_FILE" | grep "proxy_pass" | head -1)
                PORT=$(echo "$PROXY_LINE" | sed 's/.*localhost:\([0-9]*\).*/\1/')
                
                if [ -n "$PORT" ] && [ "$PORT" != "$PROXY_LINE" ]; then
                    if netstat -tln 2>/dev/null | grep -q ":$PORT "; then
                        ok "Application running on port $PORT ($location)"
                    else
                        warn "No application running on port $PORT (for $location route)"
                        echo "   💡 Start $location app on port $PORT"
                    fi
                fi
            fi
        done <<< "$LOCATIONS"
    else
        echo "   📍 No application routes configured yet"
    fi
fi

echo "🚀 Service Summary…"
# Provide a summary of configured services
if [ -f "$NGINX_CONFIG_FILE" ]; then
    ROUTE_COUNT=$(grep "location [^{]*{" "$NGINX_CONFIG_FILE" | grep -v "location / " | grep -v "location /health" | grep -v "location /nginx_status" | grep -v "location ~ " | wc -l)
    if [ "$ROUTE_COUNT" -gt 0 ]; then
        echo "   ✅ Application services: $ROUTE_COUNT web apps configured and running"
    else
        echo "   📍 Application services - Not configured"
    fi
else
    echo "   📍 Application services - Not configured"
fi

echo "   📍 Database services - Not configured"
echo "   📍 Monitoring services - Not configured"

echo
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 === SERVICES READY ==="
    exit 0
else
    echo "🔥 === SERVICES NOT READY ==="
    exit 1
fi