# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0-3] - 2025-09-19

### Added
- **VNC access** - direct access to desktop environment
- **SSH key authentication** from OpenNebula context variables
- Enhanced Phoenix RTOS container startup with animation and progress indicators
- Automatic Docker service startup and container management
- Web-based Phoenix RTOS interface on port 8080
- Improved test suite with container responsiveness checks

### Fixed
- Container startup reliability with proper wait mechanisms
- VNC service availability verification
- SSH key injection and authentication flow

## [1.0.0-2] - 2025-09-18

### Added
- VNC graphics console access for direct VM interaction
- Enhanced user input descriptions with practical examples
- Hypervisor and scheduling requirements for proper deployment
- Improved template configuration for marketplace standards

### Fixed
- SSH connectivity issues with proper context variable resolution
- Template instantiation reliability improvements

## [1.0.0-1] - 2025-09-18

### Added

Create new Phoenix RTOS appliance for OpenNebula Community Marketplace.

- Based on Phoenix RTOS real-time operating system running in Docker
- Ubuntu 22.04 LTS base operating system with Docker Engine CE pre-installed
- Phoenix RTOS container (pablodelarco/phoenix-rtos-one:latest) ready to run
- Interactive Phoenix RTOS shell access with BusyBox environment
- Real-time microkernel architecture with POSIX-compliant API
- Built-in networking stack and system utilities
- Configurable container parameters (ports, volumes, environment variables)
- Support for custom Docker registry authentication
- Comprehensive documentation and usage examples
- Automated testing and certification compliance
