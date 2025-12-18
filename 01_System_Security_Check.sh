#!/bin/bash
# host-docker-readiness.sh
# POSIX shell – emoji-enhanced output 🚀

FAIL=0

ok()   { printf "✅ [OK]   %s\n" "$1"; }
warn() { printf "⚠️  [WARN] %s\n" "$1"; }
fail() { printf "❌ [FAIL] %s\n" "$1"; FAIL=1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

echo "🔍 Checking required tools…"
for cmd in \
    awk grep sed cut df free uptime mount date \
    systemctl ip ping getent \
    docker cloudflared
do
    need_cmd "$cmd"
done

echo "🖥️  System state checks…"
uptime >/dev/null 2>&1 && ok "System booted" || fail "Uptime unavailable"

systemctl is-system-running --quiet \
    && ok "Systemd running cleanly" \
    || warn "Systemd not fully running"

systemctl --failed --quiet \
    && ok "No failed systemd units" \
    || fail "Failed systemd units present"

LOAD=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | tr -d ' ')
[ -n "$LOAD" ] && ok "Load average readable" || fail "Load average unavailable"

echo "🧠 Memory & storage…"
FREE_MEM=$(free -m | awk '/Mem:/ {print $4}')
[ "$FREE_MEM" -gt 100 ] 2>/dev/null \
    && ok "Free RAM available" \
    || warn "Low free RAM"

free | awk '/Swap:/ {exit ($2>0?0:1)}' \
    && ok "Swap present" \
    || warn "No swap configured"

mount | grep ' on / ' | grep -q '(rw' \
    && ok "Root filesystem is read-write" \
    || fail "Root filesystem not writable"

ROOT_FREE=$(df / | awk 'NR==2 {print $4}')
[ "$ROOT_FREE" -gt 102400 ] 2>/dev/null \
    && ok "Root disk space sufficient" \
    || fail "Low disk space on /"

dmesg | grep -iE 'ext4|xfs|btrfs' | grep -i error >/dev/null 2>&1 \
    && warn "Filesystem errors detected" \
    || ok "No filesystem errors reported"

echo "⏰ Time configuration…"
timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes \
    && ok "Clock synchronized" \
    || warn "Clock not synchronized"

timedatectl show -p Timezone --value >/dev/null 2>&1 \
    && ok "Timezone set" \
    || fail "Timezone not configured"

echo "🌐 Network checks…"
ip link show up | grep -q 'state UP' \
    && ok "Network interface up" \
    || fail "No active network interface"

ip route | grep -q default \
    && ok "Default route present" \
    || fail "No default route"

getent hosts example.com >/dev/null 2>&1 \
    && ok "DNS resolution works" \
    || fail "DNS resolution failed"

# DNS Configuration Analysis
echo "🔍 DNS configuration analysis…"
CURRENT_DNS=$(resolvectl status | grep "DNS Servers:" | head -1 | awk '{print $3}' | sed 's/#.*//')
if [[ "$CURRENT_DNS" =~ ^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
    warn "Using local DNS ($CURRENT_DNS) - may have slower updates"
    echo "💡 Consider using public DNS: 1.1.1.1 (Cloudflare) or 8.8.8.8 (Google)"
elif [[ "$CURRENT_DNS" =~ ^1\.1\.1\.1|^8\.8\.8\.8|^8\.8\.4\.4|^1\.0\.0\.1$ ]]; then
    ok "Using optimized public DNS: $CURRENT_DNS"
else
    ok "Using external DNS server: $CURRENT_DNS"
fi

# Test DNS responsiveness
if [ -n "$CURRENT_DNS" ]; then
    LOCAL_TIME=$(dig +short +time=2 cloudflare.com @"$CURRENT_DNS" 2>/dev/null | wc -l)
    if [ "$LOCAL_TIME" -gt 0 ]; then
        ok "Primary DNS server responding correctly"
    else
        warn "Primary DNS server not responding properly"
        # Test fallback
        FALLBACK_TEST=$(dig +short +time=1 cloudflare.com @1.1.1.1 2>/dev/null | wc -l)
        if [ "$FALLBACK_TEST" -gt 0 ]; then
            ok "Fallback DNS servers available"
        else
            fail "DNS resolution issues detected"
        fi
    fi
else
    warn "Could not detect current DNS server"
fi

ping -c1 -W1 1.1.1.1 >/dev/null 2>&1 \
    && ok "Outbound connectivity works" \
    || fail "No outbound connectivity"

echo "� Firewall checks…"
command -v ufw >/dev/null 2>&1 \
    && ok "UFW firewall available" \
    || warn "UFW firewall not installed"

sudo ufw status 2>/dev/null | grep -q "Status: active" \
    && ok "Firewall is active" \
    || warn "Firewall not active"

sudo ufw status 2>/dev/null | grep -q "22/tcp" \
    && ok "SSH access configured" \
    || fail "SSH access not configured - risk of lockout"

sudo ufw status 2>/dev/null | grep -q "80/tcp" \
    && ok "HTTP port (80) allowed" \
    || warn "HTTP port (80) not allowed"

sudo ufw status 2>/dev/null | grep -q "443" \
    && ok "HTTPS port (443) allowed" \
    || warn "HTTPS port (443) not allowed"

sudo ufw status verbose 2>/dev/null | grep "Default:" | grep -q "deny (incoming)" \
    && ok "Default incoming policy is deny" \
    || fail "Incoming traffic not denied by default"

sudo ufw status verbose 2>/dev/null | grep "Default:" | grep -q "allow (outgoing)" \
    && ok "Default outgoing policy is allow" \
    || warn "Outgoing traffic restricted"

sudo ufw status 2>/dev/null | grep -E "(22/tcp|ssh)" | grep -q "LIMIT" \
    && ok "SSH rate limiting enabled" \
    || warn "SSH not rate limited"

sudo ufw status verbose 2>/dev/null | grep -q "Logging: on" \
    && ok "Firewall logging enabled" \
    || warn "Firewall logging disabled"

iptables -L DOCKER-USER >/dev/null 2>&1 \
    && ok "Docker user chain exists" \
    || warn "Docker may bypass firewall rules"

docker ps --format "table {{.Ports}}" 2>/dev/null | grep -q "0.0.0.0:" \
    && warn "Docker containers exposed to all interfaces" \
    || ok "Docker ports not exposed globally"

command -v fail2ban-client >/dev/null 2>&1 \
    && ok "Fail2ban available" \
    || warn "Fail2ban not installed"

systemctl is-active --quiet fail2ban \
    && ok "Fail2ban service running" \
    || warn "Fail2ban service not running"

systemctl is-enabled --quiet fail2ban \
    && ok "Fail2ban enabled at boot" \
    || warn "Fail2ban not enabled at boot"

sudo fail2ban-client status 2>/dev/null | grep -q "Number of jail:" \
    && ok "Fail2ban jails configured" \
    || warn "No fail2ban jails configured"

sudo fail2ban-client status 2>/dev/null | grep -q "sshd" \
    && ok "SSH jail active" \
    || warn "SSH jail not active"

BANNED_COUNT=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Currently banned:" | awk '{print $3}' || echo "0")
[ "$BANNED_COUNT" -gt 0 ] 2>/dev/null \
    && warn "Currently banned IPs: $BANNED_COUNT" \
    || ok "No currently banned IPs"

echo "�🐳 Docker checks…"
systemctl is-active --quiet docker \
    && ok "Docker service running" \
    || fail "Docker service not running"

systemctl is-enabled --quiet docker \
    && ok "Docker enabled at boot" \
    || warn "Docker not enabled at boot"

docker info >/dev/null 2>&1 \
    && ok "Docker daemon responding" \
    || fail "Docker daemon not responding"

echo "📝 Logs & power…"
[ -d /etc/logrotate.d ] \
    && ok "Log rotation configured" \
    || warn "Log rotation not found"

systemctl is-active --quiet systemd-timesyncd \
    && ok "Time sync service running" \
    || warn "Time sync service not running"

loginctl show-session "$(loginctl | awk 'NR==2 {print $1}')" -p IdleHint 2>/dev/null | grep -q no \
    && ok "System not suspending" \
    || warn "Power management may suspend system"

[ -f /var/run/reboot-required ] \
    && warn "Reboot required" \
    || ok "No reboot pending"

echo
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 === HOST READY ==="
    exit 0
else
    echo "🔥 === HOST NOT READY ==="
    exit 1
fi
