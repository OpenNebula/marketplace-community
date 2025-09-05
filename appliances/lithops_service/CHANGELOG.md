# Changelog

All notable changes to this appliance will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [6.10.0-3-20250513] - 2025-05-21

### Updated

- Update Lithops repo source
- Update service template attributes

## [6.10.0-3-20250513] - 2025-05-21

### Fixed

- Fix template for Lithops Virtual Router

## [6.10.0-3-20250513] - 2025-05-13

### Added

Lithops Service now uses RabbitMQ as message broker, Lithops Workers as compute backend and MinIO as storage backend.

- Create worker appliance for AMQP backend

## [6.10.0-2-20241018] - 2025-01-09

### Added

First version of Lithops Service

- Edit Lithops appliance code to support the new ONE backend, from branch f-569 in OpenNebula/lithops repository
- Add appliance metadata for Service Template, MinIO and Lithops
