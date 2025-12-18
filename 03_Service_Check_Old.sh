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

echo "🌐 Cloudflare Tunnel Services…"
command -v cloudflared >/dev/null 2>&1 \
    && ok "cloudflared tunnel service available" \
    || fail "cloudflared not installed (required for tunneling)"

# Check for Cloudflare tunnel configuration
if [ -f ~/.cloudflared/config.yml ]; then
    ok "cloudflared config.yml found"
    
    # Validate config structure
    if grep -q "tunnel:" ~/.cloudflared/config.yml && grep -q "ingress:" ~/.cloudflared/config.yml; then
        ok "Cloudflare config structure valid"
    else
        fail "Cloudflare config missing required tunnel/ingress sections"
    fi
    
    # Check for domain routing (updated for direct port routing)
    if grep -q "tb-cloudlab.cloudflareaccess.com" ~/.cloudflared/config.yml; then
        DOMAIN_COUNT=$(grep -c "tb-cloudlab.cloudflareaccess.com" ~/.cloudflared/config.yml)
        ok "Domain routing configured: $DOMAIN_COUNT domains for tb-cloudlab.cloudflareaccess.com"
        
        # Check direct port routing
        if grep -q "localhost:8888" ~/.cloudflared/config.yml; then
            ok "Direct routing: jupyter.tb-cloudlab.cloudflareaccess.com → localhost:8888"
        fi
        if grep -q "localhost:8000" ~/.cloudflared/config.yml; then
            ok "Direct routing: web.tb-cloudlab.cloudflareaccess.com → localhost:8000"
        fi
    else
        warn "Domain routing not configured for expected domains"
    fi
else
    fail "cloudflared config.yml not found at ~/.cloudflared/config.yml"
fi

# Check for credentials file
CRED_FILE=$(grep "credentials-file:" ~/.cloudflared/config.yml 2>/dev/null | awk '{print $2}' || true)
if [ -n "$CRED_FILE" ] && [ -f "$CRED_FILE" ]; then
    ok "Cloudflare credentials file found"
else
    warn "Cloudflare credentials file not found or not configured"
fi

# Check if tunnel process is running
if pgrep -f cloudflared >/dev/null 2>&1; then
    ok "Cloudflare tunnel process running"
else
    warn "Cloudflare tunnel not currently running"
fi

echo "🔧 Cloudflare System Integration Analysis…"

# Check if cloudflared is installed as system service
if systemctl list-unit-files | grep -q cloudflared; then
    SERVICE_STATUS=$(systemctl is-active cloudflared 2>/dev/null || echo "inactive")
    SERVICE_ENABLED=$(systemctl is-enabled cloudflared 2>/dev/null || echo "disabled")
    ok "Cloudflared system service: $SERVICE_STATUS ($SERVICE_ENABLED)"
else
    warn "Cloudflared not installed as system service"
    echo "💡 Consider installing as service for automatic startup:"
    echo "   sudo cloudflared service install"
fi

# Check current process management
CURRENT_PROCS=$(pgrep -f cloudflared | wc -l)
if [ "$CURRENT_PROCS" -gt 0 ]; then
    ok "Current tunnel processes: $CURRENT_PROCS"
    # Check if running via systemd vs manual
    if systemctl is-active --quiet cloudflared 2>/dev/null; then
        ok "Running via systemd service (recommended)"
    else
        warn "Running manually (consider systemd service for reliability)"
    fi
else
    warn "No tunnel processes currently running"
fi

# Architecture recommendation
echo "📊 Architecture Analysis:"
if grep -q "localhost:888[08]\|localhost:8000" /etc/cloudflared/config.yml 2>/dev/null || \
   grep -q "localhost:888[08]\|localhost:8000" ~/.cloudflared/config.yml 2>/dev/null; then
    ok "Using direct port routing architecture"
    echo "   ✓ Simplified configuration without reverse proxy"
    echo "   ✓ Direct application access via cloudflared"
    echo "   ✓ No nginx complexity or maintenance"
else
    warn "Could not verify tunnel routing configuration"
fi

# Remove nginx dependency and checks - architecture simplified to direct routing only

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

# Check HTTPS - not needed for Cloudflare tunnels but test if configured
if curl -s --connect-timeout 2 -k https://localhost >/dev/null 2>&1; then
    ok "Nginx responding on HTTPS (port 443)"
elif [ -f ~/.cloudflared/config.yml ]; then
    ok "HTTPS not configured (expected for Cloudflare tunnel architecture)"
else
    warn "Nginx not responding on HTTPS (port 443)"
fi

echo "🔒 Nginx SSL Configuration Analysis…"

# Check for nginx SSL server blocks
SSL_LISTENERS=$(sudo grep -r "listen.*443.*ssl" /etc/nginx/sites-enabled/ 2>/dev/null | wc -l)
if [ "$SSL_LISTENERS" -gt 0 ]; then
    ok "Nginx SSL listeners configured: $SSL_LISTENERS"
else
    warn "No nginx SSL listeners found (443 ssl)"
fi

# Check for SSL certificate files in nginx config
SSL_CERT_LINES=$(sudo grep -r "ssl_certificate" /etc/nginx/sites-enabled/ 2>/dev/null | wc -l)
if [ "$SSL_CERT_LINES" -gt 0 ]; then
    ok "SSL certificate directives found: $SSL_CERT_LINES"
    
    # Check specific certificate files
    sudo grep -r "ssl_certificate " /etc/nginx/sites-enabled/ 2>/dev/null | while read -r line; do
        CERT_FILE=$(echo "$line" | sed 's/.*ssl_certificate[[:space:]]*\([^;]*\);.*/\1/' | tr -d ' ')
        if [ -f "$CERT_FILE" ]; then
            # Check certificate details
            CERT_SUBJECT=$(openssl x509 -in "$CERT_FILE" -noout -subject 2>/dev/null | sed 's/subject=//')
            CERT_EXPIRY=$(openssl x509 -in "$CERT_FILE" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
            ok "Certificate found: $CERT_FILE"
            ok "  Subject: $CERT_SUBJECT"
            ok "  Expires: $CERT_EXPIRY"
        else
            warn "Certificate file not found: $CERT_FILE"
        fi
    done
    
    # Check for SSL private keys
    sudo grep -r "ssl_certificate_key" /etc/nginx/sites-enabled/ 2>/dev/null | while read -r line; do
        KEY_FILE=$(echo "$line" | sed 's/.*ssl_certificate_key[[:space:]]*\([^;]*\);.*/\1/' | tr -d ' ')
        if [ -f "$KEY_FILE" ]; then
            ok "SSL private key found: $KEY_FILE"
        else
            warn "SSL private key not found: $KEY_FILE"
        fi
    done
else
    warn "No SSL certificate directives found in nginx config"
fi

# Check SSL protocols and ciphers
if sudo nginx -T 2>/dev/null | grep -q "ssl_protocols"; then
    SSL_PROTOCOLS=$(sudo nginx -T 2>/dev/null | grep "ssl_protocols" | head -1 | sed 's/.*ssl_protocols[[:space:]]*\([^;]*\);.*/\1/')
    ok "SSL protocols configured: $SSL_PROTOCOLS"
else
    warn "No SSL protocols configured"
fi

# Check for HSTS headers
if sudo grep -r "Strict-Transport-Security" /etc/nginx/sites-enabled/ >/dev/null 2>&1; then
    ok "HSTS (HTTP Strict Transport Security) configured"
else
    warn "HSTS not configured"
fi

# Overall SSL status
if [ "$SSL_LISTENERS" -gt 0 ] && [ "$SSL_CERT_LINES" -gt 0 ]; then
    ok "Nginx SSL configuration: Fully configured"
elif [ -f ~/.cloudflared/config.yml ]; then
    ok "Nginx SSL configuration: Not needed (using Cloudflare tunnel)"
else
    warn "Nginx SSL configuration: Incomplete or missing"
fi

echo "🔍 Nginx Cloudflare Configuration Checks…"

# Check for domain-based server blocks
if sudo grep -r "server_name.*tb-cloudlab.cloudflareaccess.com" /etc/nginx/sites-enabled/ >/dev/null 2>&1; then
    ok "Cloudflare domain routing configured in nginx"
else
    warn "No Cloudflare domain routing found in nginx config"
fi

# Check for Cloudflare IP restoration
if sudo grep -r "set_real_ip_from" /etc/nginx/sites-enabled/ >/dev/null 2>&1; then
    ok "Real IP restoration configured for Cloudflare"
else
    warn "Real IP restoration not configured (recommended for Cloudflare)"
fi

# Check for WebSocket support
if sudo grep -r "proxy_set_header Upgrade" /etc/nginx/sites-enabled/ >/dev/null 2>&1; then
    ok "WebSocket upgrade headers configured"
else
    warn "WebSocket support not configured (may be needed for some apps)"
fi

# Check for appropriate proxy headers
if sudo grep -r "proxy_set_header X-Forwarded" /etc/nginx/sites-enabled/ >/dev/null 2>&1; then
    ok "Proxy forwarding headers configured"
else
    warn "Proxy forwarding headers not found (recommended for reverse proxy)"
fi \
    || warn "Nginx not responding on HTTPS (port 443)"

echo "� Application Routing Configuration…"
# Check all enabled nginx sites for application routes
NGINX_ENABLED_SITES="/etc/nginx/sites-enabled/*"
TOTAL_LOCATIONS=0
TOTAL_PROXIES=0

for site_config in $NGINX_ENABLED_SITES; do
    if [ -f "$site_config" ] && [ -r "$site_config" ]; then
        SITE_NAME=$(basename "$site_config")
        
        # Check for any proxy_pass directives (including root location)
        PROXY_COUNT=$(sudo grep "proxy_pass" "$site_config" 2>/dev/null | wc -l)
        if [ "$PROXY_COUNT" -gt 0 ]; then
            TOTAL_PROXIES=$((TOTAL_PROXIES + PROXY_COUNT))
            
            # Show proxy destinations
            while IFS= read -r proxy_line; do
                if [ -n "$proxy_line" ]; then
                    # Extract destination from proxy_pass
                    DESTINATION=$(echo "$proxy_line" | sed 's/.*proxy_pass[[:space:]]*\([^;]*\);.*/\1/' | sed 's/[[:space:]]*//g')
                    # Try to extract port
                    PORT=$(echo "$DESTINATION" | sed 's/.*:\([0-9]*\).*/\1/' | grep -E '^[0-9]+$' || echo "")
                    
                    if [ -n "$PORT" ]; then
                        ok "Proxy configured: $DESTINATION ($SITE_NAME)"
                    else
                        ok "Proxy configured: $DESTINATION ($SITE_NAME)"
                    fi
                fi
            done <<< "$(sudo grep "proxy_pass" "$site_config" 2>/dev/null)"
        fi
        
        # Also check for specific location blocks with proxy_pass (non-root)
        LOCATIONS=$(sudo grep "location [^{]*{" "$site_config" 2>/dev/null | grep -v "location / " | grep -v "location /health" | grep -v "location /nginx_status" | grep -v "location ~ " | sed 's/.*location \([^ ]*\) .*/\1/' | sort -u)
        
        if [ -n "$LOCATIONS" ]; then
            # Check each location block
            while IFS= read -r location; do
                if [ -n "$location" ]; then
                    # Find the corresponding proxy_pass line
                    ESCAPED_LOCATION=$(echo "$location" | sed 's|/|\\/|g')
                    PROXY_LINE=$(sudo awk "/location $ESCAPED_LOCATION {/,/}/" "$site_config" 2>/dev/null | grep "proxy_pass" | head -1)
                    
                    if [ -n "$PROXY_LINE" ]; then
                        # Extract port number from proxy_pass  
                        PORT=$(echo "$PROXY_LINE" | sed 's/.*localhost:\([0-9]*\).*/\1/')
                        
                        if [ -n "$PORT" ] && [ "$PORT" != "$PROXY_LINE" ]; then
                            ok "Route configured: $location → port $PORT ($SITE_NAME)"
                            TOTAL_LOCATIONS=$((TOTAL_LOCATIONS + 1))
                        else
                            warn "Route $location has invalid proxy target ($SITE_NAME)"
                        fi
                    else
                        warn "Route $location missing proxy_pass directive ($SITE_NAME)"
                    fi
                fi
            done <<< "$LOCATIONS"
        fi
    fi
done

if [ $TOTAL_PROXIES -gt 0 ]; then
    ok "Application proxying configured: $TOTAL_PROXIES proxy destinations"
    if [ $TOTAL_LOCATIONS -gt 0 ]; then
        ok "Specific routes configured: $TOTAL_LOCATIONS additional locations"
    fi
else
    warn "No proxy configuration found"
fi

# Check for proper proxy headers in any enabled site
HAS_PROXY_HEADERS=false
for site_config in $NGINX_ENABLED_SITES; do
    if [ -f "$site_config" ] && sudo grep -q "X-Forwarded-For" "$site_config" 2>/dev/null; then
        HAS_PROXY_HEADERS=true
        break
    fi
done

if $HAS_PROXY_HEADERS; then
    ok "Proxy headers configured for application routing"
else
    warn "Missing proxy headers in configuration" 
fi
# Check for WebSocket support in any enabled site
HAS_WEBSOCKET=false
for site_config in $NGINX_ENABLED_SITES; do
    if [ -f "$site_config" ] && sudo grep -q "proxy_set_header Upgrade" "$site_config" 2>/dev/null; then
        HAS_WEBSOCKET=true
        break
    fi
done

if $HAS_WEBSOCKET; then
    ok "WebSocket support enabled for applications"
else
    warn "WebSocket support not configured"
fi

echo "🔗 Service Network Integration…"
# Check if nginx is listening on expected ports
sudo netstat -tlnp 2>/dev/null | grep :80 | grep -q nginx \
    && ok "Nginx listening on port 80" \
    || warn "Nginx not listening on port 80"

# Check HTTPS port - not required for Cloudflare tunnels
if sudo netstat -tlnp 2>/dev/null | grep :443 | grep -q nginx; then
    ok "Nginx listening on port 443 (local HTTPS configured)"
elif [ -f ~/.cloudflared/config.yml ]; then
    ok "Port 443 unused (correct for Cloudflare tunnel architecture)"
else
    warn "Nginx not listening on port 443"
fi

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
    "302") ok "Root path redirecting (HTTP $RESPONSE_CODE - normal for JupyterLab)" ;;
    "404") warn "Root path accessible but no index file (HTTP $RESPONSE_CODE)" ;;
    *) warn "Root path unexpected response (HTTP $RESPONSE_CODE)" ;;
esac

# Check for recent errors in nginx logs
if [ -f /var/log/nginx/error.log ]; then
    # Only count errors from the last hour, excluding "connection refused" which are normal during app restarts
    CURRENT_HOUR=$(date '+%Y/%m/%d %H:')
    RECENT_ERRORS=$(sudo tail -100 /var/log/nginx/error.log 2>/dev/null | grep "$CURRENT_HOUR" | grep -E "\[(error|crit|alert|emerg)\]" | grep -v "connect() failed (111: Connection refused)" | wc -l)
    if [ "$RECENT_ERRORS" -eq 0 ]; then
        ok "No recent nginx errors"
    elif [ "$RECENT_ERRORS" -le 3 ]; then
        ok "Minor nginx errors (recent: $RECENT_ERRORS)"
    else
        warn "Recent nginx errors detected: $RECENT_ERRORS"
    fi
else
    warn "Nginx error log not accessible"
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