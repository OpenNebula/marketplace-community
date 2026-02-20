# Prowler Security Platform Appliance

Prowler is the most widely used open-source cloud security platform that automates security assessments and compliance across any cloud environment. This appliance provides the full Prowler App with web dashboard, REST API, and background workers.

## Key Features

**Security Capabilities:**
- Multi-cloud support: AWS, Azure, Google Cloud, and Kubernetes
- 500+ built-in security checks and compliance controls
- Real-time security monitoring and alerting
- Automated compliance reporting

**Compliance Frameworks:**
- CIS Benchmarks (AWS, Azure, GCP, Kubernetes)
- NIST 800-53, NIST CSF
- PCI-DSS
- HIPAA
- GDPR
- SOC2
- FedRAMP
- And many more...

## Quick Start

1. **Deploy the appliance** from OpenNebula marketplace
2. **Access the web interface** at `http://VM_IP:3000`
3. **Sign up** with your email to create an admin account
4. **Add cloud providers** (AWS, Azure, GCP, or Kubernetes)
5. **Run security scans** and review findings

## Access Methods

| Method | URL/Command |
|--------|-------------|
| Web Dashboard | http://VM_IP:3000 |
| API Documentation | http://VM_IP:8080/api/v1/docs |
| SSH | `ssh root@VM_IP` (password: `opennebula`) |
| VNC | Via OpenNebula console |

## Architecture

This appliance runs the following services via Docker Compose:

| Service | Description |
|---------|-------------|
| `prowler-ui` | Next.js web dashboard (port 3000) |
| `prowler-api` | Django REST API (port 8080) |
| `mcp-server` | Model Context Protocol server for Lighthouse AI (port 8000) |
| `postgres-db` | PostgreSQL 16 database |
| `neo4j` | DozerDB graph database for Attack Paths analysis |
| `valkey` | Redis-compatible cache |
| `worker` | Celery worker for scan jobs |
| `worker-beat` | Celery beat scheduler |

## Configuration Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ONEAPP_PROWLER_UI_PORT` | Web UI port | 3000 |
| `ONEAPP_PROWLER_API_PORT` | API port | 8080 |
| `ONEAPP_PROWLER_VERSION` | Prowler version tag | stable |
| `ONEAPP_PROWLER_DB_PASSWORD` | PostgreSQL password | auto-generated |

## Management Commands

```bash
# Check service status
prowler-status

# View service logs
prowler-logs

# View specific service logs
prowler-logs prowler-api
prowler-logs prowler-ui

# Restart all services
prowler-restart

# Manual Docker Compose commands
cd /opt/prowler
docker compose ps
docker compose logs -f
docker compose restart
docker compose down
docker compose up -d
```

## Cloud Provider Configuration

### AWS
1. Go to Settings > Cloud Providers > Add Provider
2. Choose AWS and select authentication method:
   - IAM Role (recommended for EC2)
   - Access Keys
   - Assume Role

### Azure
1. Go to Settings > Cloud Providers > Add Provider
2. Choose Azure and provide:
   - Client ID
   - Tenant ID
   - Client Secret

### Google Cloud
1. Go to Settings > Cloud Providers > Add Provider
2. Choose GCP and upload service account JSON

### Kubernetes
1. Go to Settings > Cloud Providers > Add Provider
2. Choose Kubernetes and provide kubeconfig

## Data Persistence

All data is stored in `/opt/prowler/_data/`:
- `postgres/` - PostgreSQL database
- `valkey/` - Cache data
- `api/` - API configuration

## System Requirements

- **CPU**: 2 cores (minimum)
- **Memory**: 4 GB RAM (minimum), 8 GB recommended
- **Disk**: 20 GB (minimum)

## Troubleshooting

### Services not starting
```bash
cd /opt/prowler
docker compose logs
```

### Database connection issues
```bash
docker compose exec postgres-db pg_isready
```

### Reset all data
```bash
cd /opt/prowler
docker compose down -v
rm -rf _data/*
docker compose up -d
```

## Documentation

- [Prowler Documentation](https://docs.prowler.com/)
- [Prowler GitHub](https://github.com/prowler-cloud/prowler)
- [OpenNebula Documentation](https://docs.opennebula.io/)

## License

Prowler is licensed under the Apache License 2.0.
