#!/bin/bash
# 02_Platform_Check.sh
# Container platform readiness check for Docker 🚀

FAIL=0

ok()   { printf "✅ [OK]   %s\n" "$1"; }
warn() { printf "⚠️  [WARN] %s\n" "$1"; }
fail() { printf "❌ [FAIL] %s\n" "$1"; FAIL=1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

echo "🔍 Checking required platform tools…"
for cmd in \
    docker systemctl
do
    need_cmd "$cmd"
done

echo "🐳 Docker Platform Checks…"
systemctl is-active --quiet docker \
    && ok "Docker service running" \
    || fail "Docker service not running"

systemctl is-enabled --quiet docker \
    && ok "Docker enabled at boot" \
    || warn "Docker not enabled at boot"

docker info >/dev/null 2>&1 \
    && ok "Docker daemon responding" \
    || fail "Docker daemon not responding"

docker version --format '{{.Server.Version}}' >/dev/null 2>&1 \
    && ok "Docker version accessible" \
    || fail "Docker version check failed"

docker system df >/dev/null 2>&1 \
    && ok "Docker disk usage readable" \
    || fail "Docker disk usage check failed"

docker network ls | grep -q bridge \
    && ok "Docker bridge network available" \
    || fail "Docker bridge network missing"

docker ps >/dev/null 2>&1 \
    && ok "Docker container list accessible" \
    || fail "Cannot list Docker containers"

docker images >/dev/null 2>&1 \
    && ok "Docker image list accessible" \
    || fail "Cannot list Docker images"

# Docker functionality and capability checks
docker info --format '{{.Driver}}' 2>/dev/null | grep -q . \
    && ok "Docker storage driver present" \
    || fail "No Docker storage driver"

docker ps -a --filter "status=restarting" | tail -n +2 | grep -q . \
    && fail "Containers stuck restarting" \
    || ok "No restart-looping containers"

docker ps -a --filter "status=exited" | grep -q . \
    && warn "Exited containers present" \
    || ok "No exited containers"

docker run --rm busybox true >/dev/null 2>&1 \
    && ok "Docker can start containers" \
    || fail "Docker cannot start containers"

RUNNING_CONTAINERS=$(docker ps --format "table {{.Names}}" | tail -n +2 | wc -l)
[ "$RUNNING_CONTAINERS" -gt 0 ] 2>/dev/null \
    && ok "Running containers: $RUNNING_CONTAINERS" \
    || warn "No containers currently running"

TOTAL_IMAGES=$(docker images -q | wc -l)
[ "$TOTAL_IMAGES" -gt 0 ] 2>/dev/null \
    && ok "Available images: $TOTAL_IMAGES" \
    || warn "No Docker images available"

echo "🐳 Docker Platform Integration…"
# Check for common Docker networks
docker network ls | grep -q bridge \
    && ok "Default bridge network exists" \
    || fail "Default bridge network missing"

# Check if any containers are exposing web ports
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -E "(80|443|8080|3000|8000|8888)" >/dev/null 2>&1 \
    && ok "Web containers detected" \
    || warn "No web containers running"

echo "📊 Platform Resource Usage…"
DOCKER_SPACE=$(docker system df --format "table {{.Type}}\t{{.Size}}" | tail -n +2 | awk '{total+=$2} END {print total}' 2>/dev/null || echo "0")
[ -n "$DOCKER_SPACE" ] \
    && ok "Docker space usage trackable" \
    || warn "Cannot track Docker space usage"

# Check Docker compose availability (both V1 and V2)
if command -v docker-compose >/dev/null 2>&1; then
    ok "Docker Compose V1 available"
elif docker compose version >/dev/null 2>&1; then
    ok "Docker Compose V2 available"
else
    warn "Docker Compose not installed"
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 === PLATFORM READY ==="
    exit 0
else
    echo "🔥 === PLATFORM NOT READY ==="
    exit 1
fi