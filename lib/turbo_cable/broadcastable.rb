require 'net/http'
require 'json'

module TurboCable
  # Provides Turbo Streams broadcasting methods for ActiveRecord models
  # Drop-in replacement for Turbo::Streams::Broadcastable
  #
  # Hybrid async/sync approach:
  # - _later_to methods: Use Active Job if available, otherwise synchronous
  # - Non-_later_to methods: Always synchronous
  module Broadcastable
    extend ActiveSupport::Concern

    # Async broadcast methods (truly async if Active Job is configured)
    def broadcast_replace_later_to(stream_name, **options)
      if async_broadcast_available?
        enqueue_broadcast_job(stream_name, action: :replace, **options)
      else
        broadcast_action_now(stream_name, action: :replace, **options)
      end
    end

    def broadcast_update_later_to(stream_name, **options)
      if async_broadcast_available?
        enqueue_broadcast_job(stream_name, action: :update, **options)
      else
        broadcast_action_now(stream_name, action: :update, **options)
      end
    end

    def broadcast_append_later_to(stream_name, **options)
      if async_broadcast_available?
        enqueue_broadcast_job(stream_name, action: :append, **options)
      else
        broadcast_action_now(stream_name, action: :append, **options)
      end
    end

    def broadcast_prepend_later_to(stream_name, **options)
      if async_broadcast_available?
        enqueue_broadcast_job(stream_name, action: :prepend, **options)
      else
        broadcast_action_now(stream_name, action: :prepend, **options)
      end
    end

    # Synchronous broadcast methods (always immediate)
    def broadcast_replace_to(stream_name, **options)
      broadcast_action_now(stream_name, action: :replace, **options)
    end

    def broadcast_update_to(stream_name, **options)
      broadcast_action_now(stream_name, action: :update, **options)
    end

    def broadcast_append_to(stream_name, **options)
      broadcast_action_now(stream_name, action: :append, **options)
    end

    def broadcast_prepend_to(stream_name, **options)
      broadcast_action_now(stream_name, action: :prepend, **options)
    end

    def broadcast_remove_to(stream_name, target:)
      turbo_stream_html = <<~HTML
        <turbo-stream action="remove" target="#{target}">
        </turbo-stream>
      HTML

      broadcast_turbo_stream(stream_name, turbo_stream_html)
    end

    private

    # Check if async broadcasting is available (Active Job with non-inline adapter)
    def async_broadcast_available?
      defined?(ActiveJob) &&
        defined?(TurboCable::BroadcastJob) &&
        ActiveJob::Base.queue_adapter_name != :inline
    end

    # Enqueue broadcast job for async processing
    def enqueue_broadcast_job(stream_name, action:, target: nil, partial: nil, html: nil, locals: {})
      TurboCable::BroadcastJob.perform_later(
        stream_name,
        action: action,
        model_gid: to_global_id.to_s,
        target: target,
        partial: partial,
        html: html,
        locals: locals
      )
    end

    # Broadcast immediately (synchronous)
    def broadcast_action_now(stream_name, action:, target: nil, partial: nil, html: nil, locals: {})
      # Determine target - use explicit target or derive from model
      target ||= "#{self.class.name.underscore}_#{id}"

      # Generate content HTML
      content_html = if html
        html
      elsif partial
        # Render partial with locals
        ApplicationController.render(partial: partial, locals: locals.merge(self.class.name.underscore.to_sym => self))
      else
        # Render default partial for this model
        ApplicationController.render(partial: self, locals: locals)
      end

      # Generate Turbo Stream HTML
      turbo_stream_html = <<~HTML
        <turbo-stream action="#{action}" target="#{target}">
          <template>
            #{content_html}
          </template>
        </turbo-stream>
      HTML

      broadcast_turbo_stream(stream_name, turbo_stream_html)
    end

    def broadcast_turbo_stream(stream_name, html)
      uri = URI(ENV.fetch('TURBO_CABLE_BROADCAST_URL', "http://localhost:#{ENV.fetch('PORT', 3000)}/_broadcast"))
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
      request.body = {
        stream: stream_name,
        data: html
      }.to_json

      http.request(request)
    rescue => e
      Rails.logger.error("Broadcast failed: #{e.message}") if defined?(Rails)
    end
  end
end
