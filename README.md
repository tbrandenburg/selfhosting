# Selfhosting Environment with Cloudflare Tunnels

A complete selfhosting environment with security hardening, Docker platform, and Cloudflare tunnel integration for secure application access.

## Architecture

**Direct Cloudflare Tunnel Routing**
```
Internet → Cloudflare Edge (SSL) → cloudflared → Local Apps (8888, 8000)
```

- **Cloudflare Edge**: Handles SSL termination, DDoS protection, and global CDN
- **cloudflared**: Secure tunnel daemon running as system service with direct routing
- **Local Applications**: Direct access to JupyterLab (8888) and web services (8000)
- **No reverse proxy**: Simplified architecture with direct port mapping

### Domain Configuration
- `app1.yourdomain.com` → `localhost:8888` (JupyterLab)
- `app2.yourdomain.com` → `localhost:8000` (Web Application)

> **Access URLs:**
> - **Application 1**: https://app1.yourdomain.com
> - **Application 2**: https://app2.yourdomain.com
>
> **Note**: Replace `yourdomain.com` with your actual domain configured in `/etc/cloudflared/config.yml`.

## System Components

### Security Layer (`01_System_Security_Check.sh`)
Validates and configures system-level security:
- **System Health**: Boot status, systemd, load average, memory, disk space
- **Network**: Interface status, routing, DNS resolution, connectivity
- **Firewall (UFW)**: Active with ports 22, 80, 443, 8000, 8888 allowed
- **Intrusion Prevention (fail2ban)**: SSH protection with active jails
- **Docker Security**: Port exposure checks and firewall integration
- **Required Tools**: cloudflared availability, Docker platform

### Platform Layer (`02_Platform_Check.sh`)
Verifies Docker container platform readiness:
- **Docker Service**: Running, enabled, responsive daemon
- **Container Management**: Image/container listing, storage driver
- **Network Integration**: Bridge networks, nginx integration network
- **Resource Monitoring**: Disk usage tracking, container health
- **Docker Compose V2**: Modern container orchestration support

### Service Layer (`03_Service_Check.sh`)
Validates Cloudflare tunnel direct routing:
- **Cloudflare Tunnel**: Service status, configuration validation, domain routing
- **System Integration**: Systemd service management, auto-startup configuration
- **Direct Access**: Local application port verification and connectivity
- **Architecture Validation**: Direct routing configuration verification

### Tunnel Management (`04_Create_Tunnel.sh`)
Manages Cloudflare tunnel lifecycle:
- **System Service**: Automatic detection and management via systemd
- **Configuration Validation**: Tunnel and credentials file verification
- **Status Reporting**: Real-time tunnel connection status
- **Service Control**: Start, stop, restart tunnel connections

## Cloudflare Tunnel Configuration

**Secure Direct Routing Setup:**
- **SSL Termination**: At Cloudflare edge with auto-managed certificates
- **Domain Routing**: Subdomain-based application routing
- **System Service**: Automatic startup and failure recovery
- **Zero Configuration**: No local SSL certificates required

**Key Features:**
- Automatic SSL certificate management for your custom domain
- DDoS protection and global CDN acceleration
- No firewall port configuration required (outbound only)
- Built-in access control via Cloudflare Access (optional)

## SSL/TLS Architecture

**Cloudflare Edge Termination:**
- **Certificate**: Auto-generated for your custom domain via Cloudflare
- **Protocols**: TLS 1.2, 1.3 with modern cipher suites
- **Management**: Automatic renewal and deployment
- **Performance**: Global edge optimization

**Local Requirements:**
- No local certificates needed
- HTTP-only internal communication
- Simplified configuration and maintenance

## Usage

### Initial Setup
```bash
# 1. Authenticate with Cloudflare
cloudflared tunnel login

# 2. Create tunnel
cloudflared tunnel create my-tunnel

# 3. Configure DNS records in Cloudflare Dashboard
# 4. Update config with tunnel ID

# 5. Run system validation
make check

# 6. Install as system service (automatic)
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

### Available Commands
```bash
make check           # Run all system readiness checks
make serve          # Start/restart tunnel (via systemd)
make clean          # Stop tunnel service  
./04_Create_Tunnel.sh status  # Detailed tunnel status
```

### System Service Management
```bash
# Service control
sudo systemctl start|stop|restart cloudflared
sudo systemctl status cloudflared

# Log monitoring
sudo journalctl -u cloudflared -f

# Configuration
/etc/cloudflared/config.yml
```

### System Validation
The check scripts validate the complete stack:
1. **System Security**: Firewall, fail2ban, Docker security, required tools
2. **Platform Readiness**: Docker service and network availability  
3. **Service Health**: Cloudflare tunnel, system integration, SSL validation
4. **Architecture Analysis**: Direct routing confirmation, service status

All scripts must pass for the system to be considered ready for production use.

### Domain Migration
If you're currently using `*.cloudflareaccess.com` domains, migrate to your own domain:

```bash
# 1. Run the domain setup guide
./07_Own_Domain_Setup.sh

# 2. Add your domain to Cloudflare dashboard
# 3. Create DNS CNAME records pointing to your tunnel
# 4. Update /etc/cloudflared/config.yml with your domain
# 5. Restart tunnel: sudo systemctl restart cloudflared
```

**Benefits of custom domain:**
- ✅ No certificate expiration issues
- ✅ Professional appearance  
- ✅ Full DNS control
- ✅ Cloudflare security features

## File Structure

```
.
├── 01_System_Security_Check.sh   # System and security validation
├── 02_Platform_Check.sh          # Docker platform checks  
├── 03_Service_Check.sh           # Cloudflare tunnel validation
├── 04_Create_Tunnel.sh           # Tunnel lifecycle management
├── Makefile                      # Automation commands
├── ~/.cloudflared/config.yml     # User tunnel configuration
├── /etc/cloudflared/config.yml   # System service configuration
└── README.md                     # This documentation
```

## Security Features

- **Zero Trust Network**: Cloudflare tunnel eliminates need for open firewall ports
- **DDoS Protection**: Built-in protection at Cloudflare edge
- **SSL Everywhere**: Automatic HTTPS with managed certificates
- **Access Control**: Optional Cloudflare Access integration
- **fail2ban**: SSH brute-force protection
- **UFW Firewall**: Configured for outbound-only tunnel connections
- **System Service**: Secure service user isolation

## Adding Applications

**Direct Routing Setup:**
1. **Add to tunnel config** (`/etc/cloudflared/config.yml`):
   ```yaml
   - hostname: newapp.yourdomain.com
     service: http://localhost:9000
   ```
2. **Configure DNS** in Cloudflare Dashboard (CNAME to TUNNEL-ID.cfargotunnel.com)
3. **Start your application** on the specified port
4. **Restart tunnel service**: `sudo systemctl restart cloudflared`

## Monitoring

- **System Health**: Comprehensive validation via check scripts
- **Tunnel Status**: `./04_Create_Tunnel.sh status`
- **Service Logs**: `sudo journalctl -u cloudflared -f`
- **Cloudflare Dashboard**: Real-time tunnel connection status
- **Metrics Endpoint**: `http://localhost:9090/metrics` (configured)

## Architecture Benefits

- ✅ **Simplified Configuration**: No local SSL certificate management
- ✅ **Global Performance**: Cloudflare's global edge network
- ✅ **Zero Firewall Config**: Outbound-only connections
- ✅ **Automatic Recovery**: Systemd service management
- ✅ **DDoS Protection**: Enterprise-grade protection included
- ✅ **Free SSL**: Wildcard certificates with automatic renewal

## Status Indicators

- ✅ **READY**: Component is properly configured and operational
- ⚠️ **WARN**: Component has minor issues but is functional  
- ❌ **FAIL**: Component is not working and requires attention

All components must show **READY** status before the tunnel service is considered production-ready.
