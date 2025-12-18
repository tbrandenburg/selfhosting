.PHONY: check serve clean status test help

# Default target
all: check

# Run all check scripts
check:
	@echo "Running system readiness checks..."
	./01_System_Security_Check.sh
	@echo ""
	./02_Platform_Check.sh
	@echo ""
	./03_Service_Check.sh

# Start cloudflared tunnel service
serve: check
	@echo "🚀 Starting tunnel service..."
	./04_Create_Tunnel.sh

# Complete integration test: check + serve + endpoint testing
test: serve
	@echo "🧪 Testing configured endpoints..."
	./05_Endpoint_Test.sh

# Clean up
clean:
	@echo "Cleaning up..."
	@sudo systemctl stop cloudflared 2>/dev/null || true
	@pkill cloudflared 2>/dev/null || true
	@echo "Cleanup complete"

# Show status
status:
	./04_Create_Tunnel.sh status

# Show available commands
help:
	@echo "🔧 Available commands:"
	@echo ""
	@echo "  make check    - Run system readiness checks"
	@echo "  make serve    - Start Cloudflare tunnel service"
	@echo "  make test     - Full integration test (check + serve + endpoint testing)"
	@echo "  make status   - Show tunnel service status"
	@echo "  make clean    - Stop tunnel service and cleanup"
	@echo "  make help     - Show this help message"
	@echo ""
	@echo "📋 Integration test flow:"
	@echo "  1. System validation (security, platform, services)"
	@echo "  2. Tunnel service startup/restart"
	@echo "  3. Endpoint connectivity testing"
