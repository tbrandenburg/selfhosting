#!/bin/sh
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

echo "🔗 Service Network Integration…"
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

# Check for recent errors in nginx logs
if [ -f /var/log/nginx/error.log ]; then
    ERROR_COUNT=$(tail -100 /var/log/nginx/error.log 2>/dev/null | grep "$(date '+%Y/%m/%d')" | wc -l)
    [ "$ERROR_COUNT" -eq 0 ] 2>/dev/null \
        && ok "No recent nginx errors" \
        || warn "Recent nginx errors detected: $ERROR_COUNT"
fi

echo "🚀 Future Service Slots…"
# Placeholder checks for future services
echo "   📍 Database services - Not configured"
echo "   📍 Application services - Not configured" 
echo "   📍 Monitoring services - Not configured"

echo
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 === SERVICES READY ==="
    exit 0
else
    echo "🔥 === SERVICES NOT READY ==="
    exit 1
fi