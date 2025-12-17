.PHONY: check serve clean status help

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

# Start ngrok tunnel
serve: check
	./04_Create_Tunnel.sh

# Clean up
clean:
	@echo "Cleaning up..."
	@pkill ngrok || true
	@echo "Cleanup complete"

# Show status
status:
	./04_Create_Tunnel.sh status
