# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2025-12-07

### Added

- Debug logging throughout the TurboCable pipeline for diagnosing intermittent issues:
  - `turbo_stream_from` helper logs when rendering stream markers
  - `broadcast_json` logs broadcast URL and response codes
  - WebSocket subscription/confirmation logging in RackHandler
  - Broadcast delivery logging with connection count

## [1.0.1] - 2025-11-04

### Fixed

- WebSocket disconnect handling improvements
- Multi-region deployment support

### Added

- Version release checklist in CLAUDE.md

## [1.0.0] - 2025-01-04

### Added

- Initial public release of TurboCable
- WebSocket-based Turbo Streams implementation with 79-85% memory savings vs Action Cable
- Full API compatibility with Action Cable's Turbo Streams integration
- RFC 6455 compliant WebSocket protocol implementation via Rack hijack
- All Turbo Stream broadcast methods (`broadcast_replace_to`, `broadcast_update_to`, `broadcast_append_to`, `broadcast_prepend_to`, `broadcast_remove_to`)
- Async variants (`broadcast_*_later_to`) with hybrid Active Job support
- Custom JSON broadcasting via `broadcast_json` for structured data
- `turbo_stream_from` helper for subscribing to streams
- Stimulus controller for client-side WebSocket management
- Auto-reconnection with 3-second delay on disconnect
- 60-second read timeout for dead connection cleanup
- Thread-safe subscription management
- Generator for one-command installation (`rails generate turbo_cable:install`)
- Comprehensive test suite (rack_handler, broadcastable, streams_helper, integration tests)
- Support for Rails 7.0+
- Support for Ruby 3.0+
- Zero external dependencies beyond Ruby stdlib

### Architecture

- Rack middleware for WebSocket upgrade handling (`/cable`)
- HTTP POST endpoint for broadcasts (`/_broadcast`, localhost-only)
- In-process connection management (single-server deployments only)
- Hybrid async/sync broadcast delivery based on Active Job configuration

### Security

- Localhost-only broadcast endpoint (127.0.0.0/8 and ::1) prevents XSS attacks
- No authentication on WebSocket connections (suitable for public broadcasts)

### Documentation

- Comprehensive README with installation, usage, and migration guide
- EXAMPLES.md with production patterns (live scoring, progress tracking, custom JSON)
- CLAUDE.md with detailed architecture, protocol specification, and development workflow
- Clear warnings about single-server constraint and when NOT to use TurboCable

### Known Limitations

- Single-server deployments only (no multi-server/horizontal scaling)
- No `stream_for` helper support
- No bidirectional WebSocket communication (server→client only)
- No Action Cable channels DSL support

[1.0.2]: https://github.com/rubys/turbo_cable/releases/tag/v1.0.2
[1.0.1]: https://github.com/rubys/turbo_cable/releases/tag/v1.0.1
[1.0.0]: https://github.com/rubys/turbo_cable/releases/tag/v1.0.0
