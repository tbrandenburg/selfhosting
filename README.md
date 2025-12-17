# Selfhosting Environment Setup

A complete selfhosting environment with security hardening, Docker platform, nginx web server, and secure ngrok tunneling.

## Architecture

**nginx as Reverse Proxy + ngrok as HTTPS tunnel**
```
Internet → ngrok (HTTPS + Auth) → nginx (HTTP:80) → apps (8080, 8888, etc.)
```

- **ngrok**: Handles external HTTPS termination, basic authentication, and secure tunneling
- **nginx**: Acts as reverse proxy, serves static files, handles internal routing to applications
- **Apps**: Individual services running on different ports (Docker containers or local services)

## System Components

### Security Layer (`01_System_Security_Check.sh`)
Validates and configures system-level security:
- **System Health**: Boot status, systemd, load average, memory, disk space
- **Network**: Interface status, routing, DNS resolution, connectivity
- **Firewall (UFW)**: Active with ports 22, 80, 443, 8000, 8888 allowed
- **Intrusion Prevention (fail2ban)**: SSH protection with active jails
- **Docker Security**: Port exposure checks and firewall integration
- **Logging**: Log rotation and time synchronization

### Platform Layer (`02_Platform_Check.sh`)
Verifies Docker container platform readiness:
- **Docker Service**: Running, enabled, responsive daemon
- **Container Management**: Image/container listing, storage driver
- **Network Integration**: Bridge networks, nginx integration network
- **Resource Monitoring**: Disk usage tracking, container health
- **Docker Compose V2**: Modern container orchestration support

### Service Layer (`03_Service_Check.sh`)
Validates web services and tunneling:
- **Tunnel Services**: ngrok/tmole availability and configuration files
- **Nginx Web Server**: Service status, configuration validation, HTTP/HTTPS responses
- **Network Integration**: Port binding, Docker network connectivity
- **Health Monitoring**: Access/error logs, health endpoints, error detection
- **Configuration Validation**: ngrok-server.yml and traffic-policy.yml presence

## nginx Configuration

**Modern Security-Hardened Setup:**
- HTTP/2 support with SSL/TLS encryption
- Security headers: HSTS, CSP, X-Frame-Options, etc.
- Self-signed certificates for local HTTPS
- Health endpoint (`/health`) for monitoring
- Docker network integration for container proxying
- Error and access logging

**Key Features:**
- Serves static content from `/var/www/html`
- Ready for reverse proxy configuration to backend applications
- Optimized for Docker container integration

## ngrok Configuration

**Secure Tunneling Setup:**
- Single HTTPS endpoint with random ngrok domain
- Basic authentication with predefined credentials
- Traffic policy enforcement via external file
- Console UI and logging enabled
- Configuration inheritance from main ngrok.yml

**Authentication:**
- Basic Authentication with username + password

## Usage

### Initial Setup
```bash
# 1. Configure ngrok authentication
ngrok config add-authtoken <YOUR_TOKEN>

# 2. Run system validation
make check

# 3. Start secure tunnel
make serve
```

### Available Commands
```bash
make check    # Run all system readiness checks
make serve    # Start ngrok tunnel with basic auth
make clean    # Stop ngrok tunnels
make help     # Show available commands
```

### System Validation
The check scripts validate the complete stack:
1. **System Security**: Firewall, fail2ban, Docker security
2. **Platform Readiness**: Docker service and network availability  
3. **Service Health**: nginx, ngrok configuration, monitoring

All scripts must pass for the system to be considered ready for production use.

## File Structure

```
.
├── 01_System_Security_Check.sh   # System and security validation
├── 02_Platform_Check.sh          # Docker platform checks
├── 03_Service_Check.sh           # Web service validation
├── Makefile                      # Automation commands
├── ngrok-server.yml              # Server-specific ngrok config
├── traffic-policy.yml            # Basic auth traffic policy
└── README.md                     # This documentation
```

## Security Features

- **UFW Firewall**: Configured with minimal required ports
- **fail2ban**: SSH brute-force protection with active monitoring
- **Basic Authentication**: ngrok tunnel protection with multiple user accounts
- **HTTPS Everywhere**: End-to-end encryption from internet to nginx
- **Security Headers**: Modern web security headers in nginx
- **Docker Security**: Port exposure validation and network isolation

## Adding Applications

To add new applications behind nginx:

1. **Run your app** on a local port (e.g., 8080)
2. **Configure nginx** to proxy to your app:
   ```nginx
   location /myapp {
       proxy_pass http://localhost:8080;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
   }
   ```
3. **Restart nginx**: `sudo systemctl reload nginx`
4. **Access via ngrok**: `https://your-domain.ngrok.dev/myapp`

## Monitoring

- **System Health**: All check scripts provide comprehensive validation
- **nginx Logs**: `/var/log/nginx/access.log` and `/var/log/nginx/error.log`
- **ngrok Web UI**: `http://localhost:4040` for tunnel status
- **Health Endpoint**: `https://your-domain.ngrok.dev/health` for service validation

## Status Indicators

- ✅ **READY**: Component is properly configured and operational
- ⚠️ **WARN**: Component has minor issues but is functional  
- ❌ **FAIL**: Component is not working and requires attention

All components must show **READY** status before starting the tunnel service.
