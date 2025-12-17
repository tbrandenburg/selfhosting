.PHONY: check serve clean

# Default target
all: check

# Run all check scripts
check:
	@echo "🔍 Running system readiness checks..."
	./01_System_Security_Check.sh
	@echo ""
	./02_Platform_Check.sh
	@echo ""
	./03_Service_Check.sh

# Start ngrok tunnel to nginx with HTTPS and basic auth
serve: check
	@echo "🚀 Starting ngrok HTTPS tunnel to nginx with basic authentication..."
	@if [ ! -f ~/.config/ngrok/ngrok.yml ]; then \
		echo "❌ No ngrok config found. Please run 'ngrok config add-authtoken <YOUR_TOKEN>' first"; \
		echo "Get your token from: https://dashboard.ngrok.com/get-started/your-authtoken"; \
		exit 1; \
	fi
	@echo "� Using configurations from ~/.config/ngrok/ (ngrok-server.yml and traffic-policy.yml)"
	@echo "🚀 Starting ngrok tunnel in background..."
	@pkill ngrok 2>/dev/null || true
	@sleep 2
	@nohup ngrok start --config ~/.config/ngrok/ngrok.yml --config ~/.config/ngrok/ngrok-server.yml --all > ngrok.log 2>&1 & \
	NGROK_PID=$$!; \
	echo "🧩 ngrok process started with PID $$NGROK_PID"; \
	sleep 3; \
	echo "⏳ Waiting for ngrok API to become available..."; \
	for i in $$(seq 1 15); do \
		url=$$(curl -s --max-time 2 http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -o 'https://[^"]*' | head -n 1 || true); \
		if [ -n "$$url" ]; then \
			echo "✅ ngrok tunnel established: $$url"; \
			echo "🔐 Basic Authentication Required!"; \
			echo "📊 Web Interface: http://localhost:4040"; \
			echo "🛑 Stop tunnel: make clean"; \
			exit 0; \
		fi; \
		echo "   ...still waiting ($$i/15)"; \
		if [ $$(($$i % 5)) -eq 0 ]; then \
			echo "🔍 Partial ngrok log:"; \
			tail -n 5 ngrok.log 2>/dev/null || true; \
		fi; \
		sleep 2; \
	done; \
	echo "❌ ngrok tunnel failed to start within timeout."; \
	echo "🧾 Full ngrok log output for debugging:"; \
	cat ngrok.log 2>/dev/null || true; \
	echo "🧨 Killing ngrok process PID $$NGROK_PID"; \
	kill $$NGROK_PID 2>/dev/null || true; \
	exit 1

# Clean up
clean:
	@echo "🧹 Cleaning up..."
	@pkill ngrok || true
	@echo "✅ Cleanup complete"

# Show ngrok tunnel status
status:
	@echo "📊 Ngrok Tunnel Status:"
	@if pgrep ngrok > /dev/null; then \
		url=$$(curl -s --max-time 2 http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -o 'https://[^"]*' | head -n 1 || true); \
		if [ -n "$$url" ]; then \
			echo "   ✅ HTTPS: $$url → http://localhost:80"; \
		else \
			echo "   ℹ️  ngrok running, check: http://localhost:4040"; \
		fi \
	else \
		echo "   ❌ ngrok not running - run 'make serve' to start"; \
	fi

# Show help
help:
	@echo "🚀 Selfhosting Makefile Commands:"
	@echo ""
	@echo "  make check          - Run all system readiness checks"
	@echo "  make serve          - Start ngrok HTTPS tunnel to nginx with basic auth"
	@echo "  make status         - Show ngrok tunnel status"
	@echo "  make clean          - Stop ngrok tunnels"
	@echo "  make help           - Show this help"
	@echo ""
	@echo "🔑 First Time Setup:"
	@echo "  1. Get authtoken: https://dashboard.ngrok.com/get-started/your-authtoken"
	@echo "  2. Run: ngrok config add-authtoken <YOUR_TOKEN>"
	@echo "  3. Run: make serve"
	@echo ""
	@echo "🔐 Default Basic Auth Credentials:"
	@echo "  Username: selfhost  Password: secure123"
	@echo "  Username: admin     Password: ngrok456"