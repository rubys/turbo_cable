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
- **Bidirectional WebSocket communication** - Client→Server data flow over WebSockets (chat apps, collaborative editing, real-time drawing)
- **Action Cable channels** - Custom channels with server-side actions and the channels DSL

**If you need cross-server broadcasts or bidirectional WebSocket communication, stick with Action Cable + Redis/Solid Cable.** TurboCable only broadcasts within a single Rails process and only supports server→client Turbo Streams.

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
- **Hybrid async/sync** - Uses Active Job when available, otherwise synchronous (transparent)
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

> **💡 Want real-world examples?** See [EXAMPLES.md](EXAMPLES.md) for patterns drawn from production applications: live scoring, progress tracking, background job output, and more.

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

### Custom JSON Broadcasting

For use cases that need structured data instead of HTML (progress bars, charts, interactive widgets), use `TurboCable::Broadcastable.broadcast_json`:

```ruby
class OfflinePlaylistJob < ApplicationJob
  def perform(user_id)
    stream_name = "playlist_progress_#{user_id}"

    # Broadcast JSON updates
    TurboCable::Broadcastable.broadcast_json(stream_name, {
      status: 'processing',
      progress: 50,
      message: 'Processing files...'
    })
  end
end
```

**JavaScript handling** (in a Stimulus controller):

```javascript
connect() {
  document.addEventListener('turbo:stream-message', this.handleMessage.bind(this))
}

handleMessage(event) {
  const { stream, data } = event.detail
  if (stream === 'playlist_progress_123') {
    console.log(data.progress)  // 50
    this.updateProgressBar(data.progress, data.message)
  }
}
```

The Stimulus controller automatically dispatches `turbo:stream-message` CustomEvents when receiving JSON data (non-HTML strings). See [EXAMPLES.md](EXAMPLES.md#custom-json-broadcasting) for a complete working example with progress tracking.

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
{"type": "message", "stream": "progress", "data": {"status": "processing", "progress": 50}}
{"type": "ping"}
```

The `data` field can contain either:
- **String**: Turbo Stream HTML (automatically processed as DOM updates)
- **Object**: Custom JSON data (dispatched as `turbo:stream-message` event)

### Broadcast Endpoint

```bash
POST /_broadcast
Content-Type: application/json

# Turbo Stream HTML
{
  "stream": "counter_updates",
  "data": "<turbo-stream action=\"replace\" target=\"counter\">...</turbo-stream>"
}

# Custom JSON
{
  "stream": "progress_updates",
  "data": {"status": "processing", "progress": 50, "message": "Processing..."}
}
```

## How It Works

1. **Rack Middleware**: Intercepts `/cable` requests and upgrades to WebSocket
2. **Stimulus Controller**: Discovers `turbo_stream_from` markers and subscribes
3. **Broadcast Endpoint**: Rails broadcasts via HTTP POST to `/_broadcast`
4. **WebSocket Distribution**: Middleware forwards updates to subscribed clients

**Critical architectural constraint:** All components (WebSocket server, Rails app, broadcast endpoint) run in the same process. This is why cross-server broadcasting isn't supported.

## Security

### Broadcast Endpoint Protection

The `/_broadcast` endpoint is **restricted to localhost only** (127.0.0.0/8 and ::1). This prevents external attackers from broadcasting arbitrary HTML to connected clients.

**Why this matters:** An unprotected broadcast endpoint would allow XSS attacks - anyone who could POST to `/_broadcast` could inject malicious HTML into user browsers.

**Why localhost-only is safe:** Since TurboCable runs in-process with your Rails app, all broadcasts originate from the same machine. External access is never needed and would indicate an attack.

**Network configuration:** Ensure your firewall/reverse proxy doesn't forward external requests to `/_broadcast`. This endpoint should never be exposed through nginx, Apache, or any proxy.

## Compatibility

- **Rails:** 7.0+ (tested with 8.0+)
- **Ruby:** 3.0+
- **Browsers:** All modern browsers with WebSocket support
- **Server:** Puma or any Rack server that supports `rack.hijack`

## Technical Details

### Action Cable Feature Differences

- **`stream_for` not supported** - Use `turbo_stream_from` instead
- **Client→Server communication** - Use standard HTTP requests (forms, fetch, Turbo Frames) instead of WebSocket channel actions
- **In-process WebSocket server** - Not a separate cable server; runs within Rails process

### Hybrid Async/Sync Behavior

TurboCable intelligently chooses between async and sync broadcasting:

**Methods with `_later_to` suffix** (e.g., `broadcast_replace_later_to`):
- ✅ **Async** - If Active Job is configured with a non-inline adapter (Solid Queue, Sidekiq, etc.), broadcasts are enqueued as jobs
- 🔄 **Sync fallback** - If no job backend exists, broadcasts happen synchronously via HTTP POST

**Methods without `_later_to`** (e.g., `broadcast_replace_to`):
- 🔄 **Always sync** - Broadcasts happen immediately, useful for callbacks like `before_destroy`

**Why hybrid?**
- **Zero dependencies** - Works out of the box without requiring a job backend
- **Performance** - Async when available prevents blocking HTTP responses
- **Flexibility** - Automatically adapts to your infrastructure

**Example:**
```ruby
# Development (no job backend) - synchronous
counter.broadcast_replace_later_to "updates"  # HTTP POST happens now

# Production (with Solid Queue) - asynchronous
counter.broadcast_replace_later_to "updates"  # Job enqueued, returns immediately
```

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
