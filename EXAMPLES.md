# Real-World Examples

This document shows real-world patterns for using TurboCable, drawn from production applications.

## Live Updates

### Live Scoring Display

**Use Case**: Multiple judges entering scores during a competition. As each score is entered, all connected clients see the update in real-time.

**View** (`app/views/scores/index.html.erb`):
```erb
<div id="scores-board">
  <%= turbo_stream_from "live-scores-#{@event.id}" %>

  <%= render @scores %>
</div>
```

**Model** (`app/models/score.rb`):
```ruby
class Score < ApplicationRecord
  after_save do
    broadcast_replace_later_to "live-scores-#{event_id}",
      partial: "scores/score",
      target: dom_id(self)
  end

  after_destroy do
    broadcast_remove_to "live-scores-#{event_id}",
      target: dom_id(self)
  end
end
```

**Controller** (optional - client updates via form, server broadcasts):
```ruby
class ScoresController < ApplicationController
  def update
    @score.update(score_params)
    # Turbo Stream broadcast happens automatically via after_save callback
    respond_to do |format|
      format.turbo_stream # Return empty response or specific update
      format.html { redirect_to scores_path }
    end
  end
end
```

**Pattern**:
- Client → Server: HTTP POST/PATCH (form submission, Turbo)
- Server → All Clients: WebSocket broadcast (Turbo Stream)

---

### Current Status Display

**Use Case**: Display which heat/round is currently active. When organizers advance to the next heat, all connected displays update automatically.

**View** (`app/views/events/show.html.erb`):
```erb
<div id="current-heat-display">
  <%= turbo_stream_from "current-heat-#{@event.id}" %>

  <h2>Now on Floor</h2>
  <%= turbo_frame_tag "current-heat" do %>
    <%= render "current_heat", heat: @event.current_heat %>
  <% end %>
</div>
```

**Model** (`app/models/event.rb`):
```ruby
class Event < ApplicationRecord
  def advance_to_next_heat!
    self.current_heat_number += 1
    save!

    broadcast_replace_to "current-heat-#{id}",
      partial: "events/current_heat",
      target: "current-heat",
      locals: { heat: current_heat }
  end
end
```

**Pattern**: Admin action triggers broadcast to all passive viewers.

---

## Progress Tracking

**Use Case**: User initiates a large file upload or batch operation. Progress bar updates in real-time without polling.

**View** (`app/views/playlists/new.html.erb`):
```erb
<div id="download-progress">
  <%= turbo_stream_from "offline_playlist_#{current_user.id}" %>

  <%= turbo_frame_tag "progress-bar" do %>
    <div class="progress">
      <div class="progress-bar" style="width: 0%">0%</div>
    </div>
  <% end %>
</div>

<%= button_to "Download Playlist", offline_playlist_path, method: :post %>
```

**Controller** (`app/controllers/playlists_controller.rb`):
```ruby
class PlaylistsController < ApplicationController
  def offline_playlist
    OfflinePlaylistJob.perform_later(current_user.id, params[:playlist_id])

    respond_to do |format|
      format.turbo_stream # Show initial progress UI
      format.html { redirect_to playlists_path, notice: "Download started..." }
    end
  end
end
```

**Job** (`app/jobs/offline_playlist_job.rb`):
```ruby
class OfflinePlaylistJob < ApplicationJob
  def perform(user_id, playlist_id)
    playlist = Playlist.find(playlist_id)
    total = playlist.songs.count

    playlist.songs.each_with_index do |song, index|
      # Process song...

      # Broadcast progress
      progress = ((index + 1).to_f / total * 100).round
      broadcast_replace_to "offline_playlist_#{user_id}",
        partial: "playlists/progress",
        target: "progress-bar",
        locals: { progress: progress }
    end

    # Broadcast completion
    broadcast_replace_to "offline_playlist_#{user_id}",
      partial: "playlists/complete",
      target: "progress-bar",
      locals: { download_url: playlist.zip_url }
  end
end
```

**Pattern**:
- User-specific stream ensures progress only goes to requesting user
- Job broadcasts updates as work progresses
- Final broadcast includes download link

**Variation - Multiple Items**: For tracking multiple parallel operations, use different target IDs:
```ruby
servers.each do |server|
  broadcast_update_to "update_progress_#{user_id}",
    target: "server-#{server.id}",  # Different target per item
    locals: { server: server, status: "Updating..." }

  server.update_configuration!

  broadcast_update_to "update_progress_#{user_id}",
    target: "server-#{server.id}",
    locals: { server: server, status: "Complete" }
end
```

---

## Custom JSON Broadcasting

**Use Case**: Send structured JSON data instead of HTML when you need custom client-side handling, such as updating a progress bar, chart, or any interactive component.

### Progress Bar with JSON Events

**View** (`app/views/playlists/show.html.erb`):
```erb
<div data-controller="offline-playlist"
     data-offline-playlist-stream-value="offline_playlist_<%= ENV['RAILS_APP_DB'] %>_<%= current_user.id %>">
  <%= turbo_stream_from "offline_playlist_#{ENV['RAILS_APP_DB']}_#{current_user.id}" %>

  <button data-action="click->offline-playlist#generate">
    Prepare Offline Version
  </button>

  <div data-offline-playlist-target="progress" class="hidden">
    <div class="progress-bar">
      <div data-offline-playlist-target="progressBar" style="width: 0%">0%</div>
    </div>
    <p data-offline-playlist-target="message">Starting...</p>
  </div>
</div>
```

**Stimulus Controller** (`app/javascript/controllers/offline_playlist_controller.js`):
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "progress", "message", "progressBar"]
  static values = { stream: String }

  connect() {
    // Listen for custom JSON events from TurboCable
    this.boundHandleMessage = this.handleMessage.bind(this)
    document.addEventListener('turbo:stream-message', this.boundHandleMessage)
  }

  disconnect() {
    document.removeEventListener('turbo:stream-message', this.boundHandleMessage)
  }

  handleMessage(event) {
    const { stream, data } = event.detail

    // Only handle events for our stream
    if (stream !== this.streamValue) return

    // Handle different message types
    switch (data.status) {
      case 'processing':
        this.updateProgress(data.progress, data.message)
        break
      case 'completed':
        this.showDownloadLink(data.download_key)
        break
      case 'error':
        this.showError(data.message)
        break
    }
  }

  generate() {
    this.buttonTarget.disabled = true
    this.progressTarget.classList.remove("hidden")

    // Trigger job via HTTP
    fetch(window.location.pathname, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content
      }
    })
  }

  updateProgress(percent, message) {
    this.progressBarTarget.style.width = `${percent}%`
    this.progressBarTarget.textContent = `${percent}%`
    this.messageTarget.textContent = message
  }

  showDownloadLink(cacheKey) {
    const downloadUrl = `${window.location.pathname}.zip?cache_key=${cacheKey}`
    this.messageTarget.innerHTML = `
      <a href="${downloadUrl}" class="download-button">Download Playlist</a>
    `
  }

  showError(message) {
    this.messageTarget.textContent = message
    this.messageTarget.classList.add("error")
  }
}
```

**Job** (`app/jobs/offline_playlist_job.rb`):
```ruby
class OfflinePlaylistJob < ApplicationJob
  def perform(event_id, user_id)
    database = ENV['RAILS_APP_DB']
    stream_name = "offline_playlist_#{database}_#{user_id}"

    # Broadcast initial status
    TurboCable::Broadcastable.broadcast_json(stream_name, {
      status: 'processing',
      progress: 0,
      message: 'Starting playlist generation...'
    })

    total_heats = Solo.joins(:heat).where(heats: { number: 1.. }).count

    if total_heats == 0
      TurboCable::Broadcastable.broadcast_json(stream_name, {
        status: 'error',
        message: 'No solos found'
      })
      return
    end

    # Process items and broadcast progress
    processed = 0
    Solo.joins(:heat).where(heats: { number: 1.. }).find_each do |solo|
      # ... do processing ...

      processed += 1
      progress = (processed.to_f / total_heats * 100).to_i

      # Broadcast progress update
      TurboCable::Broadcastable.broadcast_json(stream_name, {
        status: 'processing',
        progress: progress,
        message: "Processing heat #{processed} of #{total_heats}..."
      })
    end

    # Generate final file
    cache_key = generate_zip_file(event_id, user_id)

    # Broadcast completion
    TurboCable::Broadcastable.broadcast_json(stream_name, {
      status: 'completed',
      progress: 100,
      message: 'Playlist ready for download',
      download_key: cache_key
    })
  rescue => e
    Rails.logger.error("Playlist generation failed: #{e.message}")
    TurboCable::Broadcastable.broadcast_json(stream_name, {
      status: 'error',
      message: "Failed to generate playlist: #{e.message}"
    })
  end
end
```

**Pattern**:
- Use `TurboCable::Broadcastable.broadcast_json()` to send structured data
- JavaScript receives `turbo:stream-message` CustomEvent with `{ stream, data }`
- Stimulus controller filters events by stream name
- Full control over client-side behavior (animations, state management, etc.)

**When to use JSON vs HTML**:
- ✅ **JSON**: Progress bars, charts, interactive widgets, state machines
- ✅ **HTML**: Simple DOM updates, lists, forms, standard content

---

## Background Command Output

**Use Case**: Admin runs a long-running command. Output streams to browser as it's generated.

**View** (`app/views/admin/commands/show.html.erb`):
```erb
<div id="command-output">
  <%= turbo_stream_from "command_output_#{current_user.id}_#{@job_id}" %>

  <%= turbo_frame_tag "output-log" do %>
    <pre><code></code></pre>
  <% end %>
</div>
```

**Job** (`app/jobs/command_execution_job.rb`):
```ruby
class CommandExecutionJob < ApplicationJob
  def perform(user_id, command, job_id)
    stream_name = "command_output_#{user_id}_#{job_id}"

    Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
      stdout.each_line do |line|
        broadcast_append_to stream_name,
          partial: "admin/commands/line",
          target: "output-log code",
          locals: { line: line }
      end

      exit_status = wait_thr.value
      broadcast_append_to stream_name,
        partial: "admin/commands/status",
        target: "output-log",
        locals: { status: exit_status }
    end
  end
end
```

**Pattern**:
- Job-specific stream (includes job_id) for multiple concurrent commands
- `append` action adds new lines without replacing previous output
- Works like `tail -f` in browser

---

## Key Patterns

### Stream Naming Conventions

**Global streams** (all users see same data):
```ruby
"live-scores-#{event.id}"
"current-heat-#{event.id}"
```

**User-specific streams** (only one user sees data):
```ruby
"progress_#{user_id}"
"notifications_#{user_id}"
```

**Job-specific streams** (multiple concurrent operations):
```ruby
"job_#{job_id}_#{user_id}"
"upload_#{upload_id}"
```

**Multi-tenant streams** (isolated by tenant/database):
```ruby
"updates_#{tenant_id}_#{resource_id}"
```

### Broadcast Methods

**Replace entire element**:
```ruby
broadcast_replace_to stream, target: "element-id", partial: "path/to/partial"
```

**Update element contents**:
```ruby
broadcast_update_to stream, target: "element-id", partial: "path/to/partial"
```

**Append to list**:
```ruby
broadcast_append_to stream, target: "list-id", partial: "path/to/item"
```

**Prepend to list**:
```ruby
broadcast_prepend_to stream, target: "list-id", partial: "path/to/item"
```

**Remove element**:
```ruby
broadcast_remove_to stream, target: "element-id"
```

### When TurboCable Works Well

✅ **Real-time dashboards** - Live metrics, status displays
✅ **Progress indicators** - Upload/download/processing progress
✅ **Live updates** - Scores, votes, counts, status changes
✅ **Notifications** - User-specific alerts and messages
✅ **Background job feedback** - Show what's happening in async jobs
✅ **Multi-user coordination** - Everyone sees same current state

### When You Need Action Cable Instead

❌ **Chat applications** - Requires client→server messages over WebSocket
❌ **Collaborative editing** - Needs operational transforms over WebSocket
❌ **Real-time drawing** - Continuous client→server data stream
❌ **Gaming** - Low-latency bidirectional communication
❌ **WebRTC signaling** - Peer coordination requires bidirectional channels

**Rule of thumb**: If you can describe your feature as "when X happens on the server, update Y on all clients", TurboCable works. If you need "when user does X in browser, send message to server over WebSocket", use Action Cable.

---

## Migration from Action Cable

All of showcase's 5 Action Cable channels were pure `stream_from` channels with no custom actions. They migrated to TurboCable with **zero code changes** to views or models:

**Before** (`app/channels/scores_channel.rb`):
```ruby
class ScoresChannel < ApplicationCable::Channel
  def subscribed
    stream_from "live-scores-#{ENV['RAILS_APP_DB']}"
  end
end
```

**After**: Delete the channel file entirely. Use `turbo_stream_from` in views:
```erb
<%= turbo_stream_from "live-scores-#{@event.id}" %>
```

**If your Action Cable channel has custom action methods**, it won't migrate cleanly - you'll need to convert those to HTTP endpoints.
