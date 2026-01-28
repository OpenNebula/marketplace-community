# Changelog

All notable changes to the Prowler Security Platform appliance will be documented in this file.

## [1.0.0-1] - 2025-01-16

### Added
- Initial release of Prowler Security Platform appliance
- Full multi-container deployment with Docker Compose
- Prowler API service (Django REST Framework)
- Prowler UI (Next.js web dashboard)
- PostgreSQL 16 database for persistent storage
- Valkey cache for performance optimization
- Celery workers for background scan processing
- VNC and SSH access support
- Auto-generated secure passwords
- Helper commands: `prowler-status`, `prowler-logs`, `prowler-restart`
- Welcome message with quick start information
- Comprehensive documentation

### Components
- Prowler API: stable
- Prowler UI: stable
- PostgreSQL: 16.3-alpine
- Valkey: 7-alpine

### Supported Cloud Providers
- Amazon Web Services (AWS)
- Microsoft Azure
- Google Cloud Platform (GCP)
- Kubernetes
