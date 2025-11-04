# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the TurboCable Rails engine.

## Project Overview

TurboCable is a lightweight Rails engine that replaces Action Cable with a custom WebSocket implementation for Turbo Streams. It provides 79-85% memory savings (134-144MB per process) while maintaining full API compatibility with Action Cable's Turbo Streams integration.

**Key constraint**: TurboCable is designed for **single-server deployments only**. All WebSocket connections, Rails app, and broadcasts run in the same process. For multi-server deployments (Heroku, Kubernetes, load-balanced setups), use Action Cable with Redis/Solid Cable instead.

## Architecture

### Components

1. **Rack Middleware** (`lib/turbo_cable/rack_handler.rb`)
   - Intercepts `/cable` WebSocket upgrade requests
   - Handles `/_broadcast` HTTP POST endpoint
   - Implements RFC 6455 WebSocket protocol from scratch
   - Manages connection subscriptions and message routing
   - **60-second read timeout** for dead connection cleanup

2. **Broadcastable Module** (`lib/turbo_cable/broadcastable.rb`)
   - Provides all `broadcast_*` methods (replace, update, append, prepend, remove)
   - Uses `prepend` to override turbo-rails methods
   - Renders partials server-side (identical to Action Cable/Turbo)
   - Hybrid async/sync: uses Active Job when available, falls back to HTTP POST

3. **Streams Helper** (`app/helpers/turbo_cable/streams_helper.rb`)
   - Provides `turbo_stream_from` helper
   - Creates DOM markers for JavaScript to discover subscriptions

4. **Stimulus Controller** (`lib/generators/turbo_cable/install/templates/turbo_streams_controller.js`)
   - Client-side WebSocket connection management
   - Auto-discovers streams via DOM markers
   - Handles subscribe/unsubscribe protocol
   - Responds to ping messages with pong
   - **Auto-reconnects after 3 seconds** on any disconnect
   - Processes Turbo Stream HTML and custom JSON

5. **Engine** (`lib/turbo_cable/engine.rb`)
   - Rails integration via Railtie
   - Mounts Rack middleware
   - Prepends Broadcastable to ApplicationRecord

## WebSocket Protocol

### Message Types (JSON over WebSocket)

**Client → Server:**
```json
{"type": "subscribe", "stream": "stream_name"}
{"type": "unsubscribe", "stream": "stream_name"}
{"type": "pong"}
```

**Server → Client:**
```json
{"type": "subscribed", "stream": "stream_name"}
{"type": "message", "stream": "stream_name", "data": "<turbo-stream...>"}
{"type": "message", "stream": "stream_name", "data": {"custom": "json"}}
{"type": "ping"}
```

### Broadcast Endpoint

**POST /_broadcast** (localhost only):
```json
{
  "stream": "stream_name",
  "data": "<turbo-stream action=\"replace\" target=\"id\">...</turbo-stream>"
}
```

## Connection Health Management

### Dead Connection Detection

TurboCable implements a **60-second read timeout** to detect and clean up half-dead connections:

**Problem**: Mobile clients can disappear without cleanly closing TCP connections (network switches, background suspension, tunnel entry). Without detection, these "ghost" connections accumulate indefinitely.

**Solution**: Socket read timeout of 60 seconds (matches Navigator Go implementation):
- Set via `io.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [60, 0].pack('l_2'))`
- Located in `lib/turbo_cable/rack_handler.rb:53`
- Any connection silent for 60+ seconds triggers timeout → cleanup

**Why 60 seconds is sufficient**:
- Action Cable uses 3 seconds (aggressive for high-connection-count apps)
- TurboCable targets low-to-medium connection counts (dozens to hundreds)
- Dance showcase events: updates every few seconds, 60s cleanup is plenty fast
- Memory impact minimal: even 100 ghost connections × 60s = negligible overhead
- Client auto-reconnects within 3 seconds, real users never notice

**Design decision**: 60 seconds balances robust cleanup with simplicity. Shorter timeouts (3s) add complexity (periodic ping sending, pong tracking) with minimal benefit for typical TurboCable use cases.

### Client Reconnection

Client automatically reconnects on any disconnect:
- Connection closes → wait 3 seconds → reconnect
- Network restored → resumes subscriptions
- Server restarted → reconnects when available

This makes aggressive server-side ping/pong monitoring less critical—the client heals itself.

## Navigator Integration

TurboCable works in two deployment modes:

### 1. Development Mode (Ruby-only)

TurboCable's Rack middleware handles both WebSocket and broadcast endpoints:
- `/cable` → WebSocket server (Rack hijack)
- `/_broadcast` → HTTP broadcast endpoint
- All in-process, zero configuration needed

### 2. Production Mode (with Navigator)

Navigator provides the WebSocket infrastructure in Go:
- `/cable` → Navigator's Go WebSocket handler (`internal/cable/handler.go`)
- `/_broadcast` → Navigator's broadcast endpoint
- Rails uses HTTP POST to broadcast
- Navigator routes messages to connected clients

**Navigator location**: `/Users/rubys/git/showcase/navigator`

**Navigator cable implementation**:
- `internal/cable/handler.go` - Go WebSocket server (mirrors Ruby protocol)
- `internal/cable/handler_test.go` - Comprehensive test suite
- Also uses 60-second read timeout (handler.go:216)
- Sends JSON ping every 30 seconds (handler.go:278-283)
- Gorilla WebSocket pong handler resets read deadline

**Why Navigator**: Single Go process serves all tenants (showcase events) with shared WebSocket infrastructure, massive memory savings across multi-tenant deployment.

**Configuration**: Rails app sets `TURBO_CABLE_BROADCAST_URL` to point to Navigator's `/_broadcast` endpoint (handled automatically by showcase's configurator.rb).

## Key Files

### Ruby Implementation
- `lib/turbo_cable/rack_handler.rb` - WebSocket server (202 lines)
- `lib/turbo_cable/broadcastable.rb` - Broadcast methods (142 lines)
- `lib/turbo_cable/broadcast_job.rb` - Active Job integration (19 lines)
- `app/helpers/turbo_cable/streams_helper.rb` - turbo_stream_from helper (14 lines)
- `lib/turbo_cable/engine.rb` - Rails integration (33 lines)

### JavaScript Client
- `lib/generators/turbo_cable/install/templates/turbo_streams_controller.js` - Stimulus controller (185 lines)

### Generator
- `lib/generators/turbo_cable/install/install_generator.rb` - One-command installation

### Tests
- `test/rack_handler_test.rb` - WebSocket protocol tests
- `test/broadcastable_test.rb` - Broadcast method tests
- `test/streams_helper_test.rb` - Helper tests
- `test/integration_test.rb` - End-to-end tests

## Development Workflow

### Running Tests

```bash
# All tests
bundle exec rake test

# Specific test file
bundle exec rake test TEST=test/rack_handler_test.rb

# Verbose output
bundle exec rake test TESTOPTS="-v"
```

### Testing in a Rails App

```bash
# In your Rails app Gemfile
gem 'turbo_cable', path: '/Users/rubys/git/turbo_cable'

# Install
bundle install
rails generate turbo_cable:install

# Start server (Puma required for rack.hijack)
rails server

# Test WebSocket connection (browser console)
ws = new WebSocket('ws://localhost:3000/cable')
ws.onopen = () => ws.send(JSON.stringify({type: 'subscribe', stream: 'test'}))
ws.onmessage = (e) => console.log('Received:', e.data)

# Test broadcast (Rails console)
TurboCable::Broadcastable.broadcast_turbo_stream('test', '<h1>Hello!</h1>')
```

### Common Development Tasks

**Add new broadcast method**:
1. Add method to `lib/turbo_cable/broadcastable.rb`
2. Follow naming convention: `broadcast_{action}_to` or `broadcast_{action}_later_to`
3. Render partial or use provided HTML
4. Call `broadcast_turbo_stream(stream, html)`
5. Add test to `test/broadcastable_test.rb`

**Modify WebSocket protocol**:
1. Update `lib/turbo_cable/rack_handler.rb` (server)
2. Update `lib/generators/turbo_cable/install/templates/turbo_streams_controller.js` (client)
3. Update `internal/cable/handler.go` in Navigator (if protocol change affects production)
4. Add tests to `test/rack_handler_test.rb`

**Debug connection issues**:
- Check Rails logs for "WebSocket error:" messages
- Browser console shows connection status and messages
- Verify Puma server (rack.hijack required)
- Test `/_broadcast` endpoint: `curl -X POST http://localhost:3000/_broadcast -d '{"stream":"test","data":"hello"}' -H "Content-Type: application/json"`

## Security Considerations

### Broadcast Endpoint Protection

`/_broadcast` is **localhost-only** (127.0.0.0/8 and ::1):
- Prevents external XSS attacks (arbitrary HTML injection)
- Safe because all broadcasts originate from same machine
- Never expose through nginx/Apache/reverse proxy

**Implementation**: `lib/turbo_cable/rack_handler.rb:143-147`

### WebSocket Authentication

Currently **no authentication** on WebSocket connections:
- Suitable for public broadcasts (live scores, public counters)
- For authenticated streams, implement at application level:
  - Sign stream names with user ID
  - Verify signature in `turbo_stream_from` helper
  - Navigator/reverse proxy handles session authentication

## Compatibility

- **Rails**: 7.0+ (tested with 8.0+)
- **Ruby**: 3.0+ (uses `prepend`, modern stdlib)
- **Server**: Puma or any Rack server supporting `rack.hijack`
- **Browsers**: All modern browsers with WebSocket support (IE 10+)
- **Active Job**: Optional (async if available, sync fallback)

## Known Limitations

**Not supported**:
- ❌ Multiple Rails instances (horizontal scaling)
- ❌ Cross-server broadcasts (use Action Cable + Redis)
- ❌ `stream_for` helper (use `turbo_stream_from`)
- ❌ Bidirectional WebSocket communication (client→server data)
- ❌ Action Cable channels DSL (only Turbo Streams)

**Why these limitations exist**: TurboCable runs in-process. WebSocket server, subscription management, and broadcast endpoint share memory. This enables zero-dependency operation but prevents cross-server communication.

## Migration from Action Cable

**Before migrating**, verify single-server deployment:
- ✅ One Rails process serves all users
- ✅ No load balancer distributing across multiple instances
- ✅ No Heroku/AWS ECS/Kubernetes horizontal scaling
- ❌ If multi-server: stick with Action Cable + Redis/Solid Cable

**If single-server**:

1. Add gem to Gemfile
2. Run `rails generate turbo_cable:install`
3. Restart Rails server
4. Remove Action Cable, Redis, Solid Cable (optional cleanup)

**No code changes needed** - views and models work identically.

## Production Deployment

### With Navigator (Multi-tenant)

Rails app broadcasts via HTTP POST to Navigator's `/_broadcast` endpoint:
- Navigator handles all WebSocket connections
- Rails app is stateless (no WebSocket server)
- Navigator routes broadcasts to correct clients
- Configuration handled by `showcase/app/controllers/concerns/configurator.rb`

### Standalone (Single-tenant)

TurboCable's Rack middleware handles everything:
- No external dependencies
- No separate WebSocket server
- All in-process

**Requirements**:
- Puma server (or Rack server with hijack support)
- Single server/dyno/container
- No load balancer splitting traffic

## Troubleshooting

### WebSocket not connecting

1. Check server logs for "WebSocket upgrade failed"
2. Verify Puma is running (not WEBrick)
3. Test handshake: `curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Key: test" http://localhost:3000/cable`
4. Browser console: check for 101 Switching Protocols response

### Broadcasts not received

1. Verify subscription: browser console should show "Subscribed to stream: ..."
2. Test broadcast endpoint: `curl -X POST http://localhost:3000/_broadcast -d '{"stream":"test","data":"<h1>Test</h1>"}' -H "Content-Type: application/json"`
3. Check stream names match (case-sensitive)
4. Verify `turbo_stream_from` helper rendered (view source for data-streams attribute)

### Connection drops frequently

1. Check nginx/proxy timeout settings (may need websocket_timeout increase)
2. Verify network stability (mobile/WiFi issues?)
3. Monitor Rails logs for "WebSocket error:" messages
4. Client should auto-reconnect (check browser console for "Attempting to reconnect...")

### Memory still high

1. Verify TurboCable is actually being used (check for `/_broadcast` in logs)
2. Ensure Action Cable not still loaded (check Gemfile)
3. Monitor connection count (dead connections cleaned up after 60s)
4. Check for other memory consumers (background jobs, caching)

## Future Enhancements

Possible improvements (not currently planned):

- **WebSocket authentication**: Sign/verify stream subscriptions
- **Compressed messages**: Gzip large HTML payloads
- **Binary protocol**: Use MessagePack instead of JSON
- **Configurable timeouts**: Make 60s timeout adjustable
- **Metrics**: Connection count, message rate, latency tracking
- **Multi-process**: Share connections via Unix socket (still single-server)

## Credits

Built for the Showcase dance event management application to reduce memory usage in multi-region Fly.io deployments. Demonstrates that Action Cable's Turbo Streams functionality can be achieved with zero external dependencies and 80%+ memory savings.

**Related projects**:
- **Navigator**: `/Users/rubys/git/showcase/navigator` - Go reverse proxy with WebSocket support
- **Showcase**: `/Users/rubys/git/showcase` - Rails app using TurboCable in production
- **Counter demo**: `/Users/rubys/tmp/counter` - Minimal test application

## Contributing

Bug reports and pull requests welcome at https://github.com/rubys/turbo_cable

When submitting PRs:
1. Add tests for new functionality
2. Ensure all existing tests pass
3. Update README.md and CLAUDE.md as needed
4. Follow existing code style (RuboCop configuration provided)
