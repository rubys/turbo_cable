# TurboCable

Custom WebSocket-based Turbo Streams implementation for Rails. Drop-in replacement for Action Cable with significantly reduced memory footprint (79-85% reduction).

## Why TurboCable?

Action Cable is excellent but comes with significant memory overhead. TurboCable provides the same Turbo Streams functionality using a lightweight WebSocket implementation built on Rack hijack and RFC 6455, requiring zero external dependencies beyond Ruby's standard library.

**Memory Savings:**
- Action Cable: ~169MB per process
- TurboCable: ~25-35MB per process
- **Savings: 134-144MB (79-85% reduction)**

## Features

- ✅ **Drop-in compatibility** with Turbo Streams API
- ✅ **Zero dependencies** (only Ruby stdlib)
- ✅ **Automatic installation** via Rails generator
- ✅ **All Turbo Stream actions** (replace, update, append, prepend, remove)
- ✅ **Auto-reconnection** on connection loss
- ✅ **Thread-safe** subscription management
- ✅ **RFC 6455 compliant** WebSocket implementation

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

## How It Works

1. **Rack Middleware**: Intercepts `/cable` requests and upgrades to WebSocket
2. **Stimulus Controller**: Discovers `turbo_stream_from` markers and subscribes
3. **Broadcast Endpoint**: Rails broadcasts via HTTP POST to `/_broadcast`
4. **WebSocket Distribution**: Middleware forwards updates to subscribed clients

## Configuration

### Broadcast URL (Optional)

By default, broadcasts go to `http://localhost:3000/_broadcast`. For production with reverse proxies:

```ruby
# config/application.rb or initializer
ENV['TURBO_CABLE_BROADCAST_URL'] = 'http://localhost:3000/_broadcast'
```

## Migration from Action Cable

**Views:** No changes needed! `turbo_stream_from` works identically.

**Models:** No changes needed! All `broadcast_*` methods work identically.

**Infrastructure:** Just add the gem and run the installer. Action Cable can be removed.

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

## Compatibility

- **Rails:** 7.0+ (tested with 8.0+)
- **Ruby:** 3.0+
- **Browsers:** All modern browsers with WebSocket support

## Limitations

- No support for Action Cable channels (only Turbo Streams)
- No support for Action Cable's `stream_for` DSL (use `turbo_stream_from` instead)
- Broadcasts are in-process only (no Redis adapter yet)

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
