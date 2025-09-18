# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
