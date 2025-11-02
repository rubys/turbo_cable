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
