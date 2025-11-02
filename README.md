# TurboCable

Custom WebSocket-based Turbo Streams implementation for Rails. Provides significant memory savings (79-85% reduction) for single-server deployments.

## ⚠️ Important Limitations

**TurboCable is designed for specific use cases.** Read carefully before adopting:

### ✅ When to Use TurboCable

- **Single-server applications** - All users connect to one Rails instance
- **Development environments** - Great for local dev with live reloading
- **Single-tenant deployments** - Each customer/event runs independently
- **Resource-constrained environments** - Memory savings matter (VPS, embedded)
- **Simple real-time needs** - Basic live updates within one process

### ❌ When NOT to Use TurboCable

- **Horizontally scaled apps** - Multiple servers/dynos serving same application (Heroku, AWS ECS, Kubernetes with replicas)
- **Load-balanced production** - Multiple Rails instances behind a load balancer
- **Cross-server broadcasts** - Need to broadcast to users on different machines
- **High-availability setups** - Require Redis or Solid Cable backed pub/sub across instances
- **Shared WebSocket servers** - Multi-tenant architectures with shared cable servers

**If you need cross-server broadcasts, stick with Action Cable + Redis/Solid Cable.** TurboCable only broadcasts within a single Rails process.

## Why TurboCable?

For applications that fit the constraints above, Action Cable's memory overhead may be unnecessary. TurboCable provides the same Turbo Streams functionality using a lightweight WebSocket implementation built on Rack hijack and RFC 6455, with zero external dependencies beyond Ruby's standard library.

**Memory Savings (single server):**
- Action Cable: ~169MB per process
- TurboCable: ~25-35MB per process
- **Savings: 134-144MB (79-85% reduction)**

## Features

For applications within the constraints above:

- **Turbo Streams API compatibility** - Same `turbo_stream_from` and `broadcast_*` methods
- **Zero dependencies** - Only Ruby stdlib (no Redis, no Solid Cable, no external services)
- **Simple installation** - `rails generate turbo_cable:install`
- **All Turbo Stream actions** - replace, update, append, prepend, remove
- **Auto-reconnection** - Handles connection drops gracefully
- **Thread-safe** - Concurrent connections and broadcasts
- **RFC 6455 compliant** - Standard WebSocket protocol

## Installation

Add this line to your application's Gemfile:

```ruby
gem "turbo_cable"
```

Install the gem:

```bash
bundle install
```

Run the installer:

```bash
rails generate turbo_cable:install
```

This will:
1. Copy the Stimulus controller to `app/javascript/controllers/turbo_streams_controller.js`
2. Add `data-controller="turbo-streams"` to your `<body>` tag

Restart your Rails server and you're done!

## Usage

### In Your Views

Use `turbo_stream_from` exactly as you would with Action Cable:

```erb
<div>
  <%= turbo_stream_from "counter_updates" %>

  <span id="counter-value"><%= @counter.value %></span>
</div>
```

### In Your Models

Use the same broadcast methods you're familiar with:

```ruby
class Counter < ApplicationRecord
  def broadcast_update
    broadcast_replace_later_to "counter_updates",
      target: "counter-value",
      html: "<span id='counter-value'>#{value}</span>"
  end
end
```

**Available broadcast methods:**
- `broadcast_replace_later_to` / `broadcast_replace_to`
- `broadcast_update_later_to` / `broadcast_update_to`
- `broadcast_append_later_to` / `broadcast_append_to`
- `broadcast_prepend_later_to` / `broadcast_prepend_to`
- `broadcast_remove_to`

All methods support the same options as Turbo Streams:
- `target:` - DOM element ID
- `partial:` - Render a partial
- `html:` - Use raw HTML
- `locals:` - Pass locals to partial

### Example with Partial

```ruby
class Score < ApplicationRecord
  after_save do
    broadcast_replace_later_to "live-scores",
      partial: "scores/score",
      target: dom_id(self)
  end
end
```

## Configuration

### Broadcast URL (Optional)

By default, broadcasts go to `http://localhost:3000/_broadcast`. For production with reverse proxies:

```ruby
# config/application.rb or initializer
ENV['TURBO_CABLE_BROADCAST_URL'] = 'http://localhost:3000/_broadcast'
```

## Migration from Action Cable

**⚠️ First, verify your deployment architecture supports TurboCable.** If you have multiple Rails instances serving the same app (Heroku dynos, AWS containers, Kubernetes pods, load-balanced VPS), TurboCable won't work for you. See "When NOT to Use" above.

**If you're on a single server:**

**Views:** No changes needed! `turbo_stream_from` works identically.

**Models:** No changes needed! All `broadcast_*` methods work identically.

**Infrastructure:** Just add the gem and run the installer. Action Cable, Redis, and Solid Cable can be removed.

## Real-World Use Cases

### ✅ Good Fit

**Single VPS deployment** - One Rails server handling all traffic. Live updates for dashboards, notifications, or collaborative features within that single server.

**Development environment** - Faster startup, less memory, simpler debugging than Action Cable.

**Multi-tenant with process isolation** - Each tenant runs in a separate Rails process (like separate databases per customer). Each process has isolated WebSocket connections with no cross-tenant concerns.

**Resource-constrained deployments** - Raspberry Pi, embedded systems, or budget VPS where 134MB per instance matters.

**Prototypes and MVPs** - Get real-time features working quickly without Redis/Solid Cable infrastructure.

### ❌ Poor Fit

**Heroku with multiple dynos** - User A on dyno 1 won't see broadcasts from user B on dyno 2. Stick with Action Cable + Redis/Solid Cable.

**AWS ECS/Fargate with replicas** - Same issue - each container is isolated.

**Kubernetes with multiple pods** - Broadcasts don't cross pod boundaries.

**Any load-balanced setup** - If you have >1 Rails instance serving the same application, you need Action Cable + Redis/Solid Cable for cross-instance broadcasting.

## Protocol Specification

### WebSocket Messages (JSON)

**Client → Server:**
```json
{"type": "subscribe", "stream": "counter_updates"}
{"type": "unsubscribe", "stream": "counter_updates"}
{"type": "pong"}
```

**Server → Client:**
```json
{"type": "subscribed", "stream": "counter_updates"}
{"type": "message", "stream": "counter_updates", "data": "<turbo-stream...>"}
{"type": "ping"}
```

### Broadcast Endpoint

```bash
POST /_broadcast
Content-Type: application/json

{
  "stream": "counter_updates",
  "data": "<turbo-stream action=\"replace\" target=\"counter\">...</turbo-stream>"
}
```

## How It Works

1. **Rack Middleware**: Intercepts `/cable` requests and upgrades to WebSocket
2. **Stimulus Controller**: Discovers `turbo_stream_from` markers and subscribes
3. **Broadcast Endpoint**: Rails broadcasts via HTTP POST to `/_broadcast`
4. **WebSocket Distribution**: Middleware forwards updates to subscribed clients

**Critical architectural constraint:** All components (WebSocket server, Rails app, broadcast endpoint) run in the same process. This is why cross-server broadcasting isn't supported.

## Compatibility

- **Rails:** 7.0+ (tested with 8.0+)
- **Ruby:** 3.0+
- **Browsers:** All modern browsers with WebSocket support
- **Server:** Puma or any Rack server that supports `rack.hijack`

## Technical Limitations

### What's NOT Supported

1. **Cross-process broadcasts** - Broadcasts only reach WebSocket connections in the same Rails process. No Redis/Solid Cable adapter, no multi-server pub/sub.

2. **Horizontal scaling** - Can't scale to multiple instances of your app on different machines. Each instance would have isolated WebSocket connections.

3. **Action Cable channels** - Only Turbo Streams. No support for custom Action Cable channels or the channels DSL.

4. **Action Cable's `stream_for`** - Use `turbo_stream_from` instead.

5. **Separate cable servers** - WebSocket handling is in-process with Rails, not a standalone server.

### What IS Supported

- ✅ All Turbo Streams actions (replace, update, append, prepend, remove)
- ✅ Multiple concurrent connections per process
- ✅ Multiple streams per connection
- ✅ Partial rendering with locals
- ✅ Auto-reconnection on connection loss
- ✅ Thread-safe subscription management

## Development

After checking out the repo:

```bash
bundle install
bundle exec rake test
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rubys/turbo_cable.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Credits

Inspired by the memory optimization needs of multi-region Rails deployments. Built to prove that Action Cable's functionality can be achieved with minimal dependencies and maximum efficiency.
