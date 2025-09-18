# Changelog

All notable changes to this appliance will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0-1] - 2025-01-18

### Added

- Initial release of Custom Docker appliance
- Ubuntu 22.04 LTS base operating system
- Docker Engine CE 26.1.3 pre-installed and configured
- Docker Compose plugin support (v2.24.0+)
- Docker Buildx plugin for advanced build features
- Optional Docker registry authentication support
- Configurable Docker daemon settings via context parameters
- Customizable logging configuration (driver, max size, max files)
- Security hardened SSH configuration
- Comprehensive contextualization parameters for customization
- Automatic Docker service startup and health verification
- Support for custom Docker daemon configuration in JSON format
- Built-in cleanup and optimization routines
- Detailed service reporting and status information

### Features

- **Base OS**: Ubuntu 22.04 LTS with latest security updates
- **Docker Engine**: Version 26.1.3 with specific version pinning for stability
- **Docker Compose**: Latest plugin version for container orchestration
- **Docker Buildx**: Multi-platform build support
- **Registry Support**: Authentication with private Docker registries
- **Logging**: Configurable logging drivers and rotation policies
- **Security**: Hardened SSH configuration and proper service isolation
- **Monitoring**: Built-in health checks and service verification
- **Reconfiguration**: Support for runtime reconfiguration via context changes

### Context Parameters

- `ONEAPP_DOCKER_REGISTRY_URL`: Custom Docker registry URL
- `ONEAPP_DOCKER_REGISTRY_USER`: Docker registry username
- `ONEAPP_DOCKER_REGISTRY_PASSWORD`: Docker registry password
- `ONEAPP_DOCKER_COMPOSE_VERSION`: Docker Compose version
- `ONEAPP_DOCKER_DAEMON_CONFIG`: Custom daemon configuration (JSON)
- `ONEAPP_ENABLE_DOCKER_BUILDX`: Enable/disable Buildx plugin
- `ONEAPP_DOCKER_LOG_DRIVER`: Logging driver selection
- `ONEAPP_DOCKER_LOG_MAX_SIZE`: Maximum log file size
- `ONEAPP_DOCKER_LOG_MAX_FILE`: Maximum number of log files

### Technical Details

- **Disk Size**: 8GB (optimized for Docker usage)
- **Memory**: 2GB recommended minimum
- **CPU**: 1 vCPU minimum
- **Network**: Requires internet connectivity for Docker Hub access
- **Storage Driver**: overlay2 (default, optimized for performance)
- **Restart Policy**: Docker service configured with automatic restart
- **Live Restore**: Enabled for container persistence during daemon restarts
