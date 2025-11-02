require 'net/http'
require 'json'

module TurboCable
  # Provides Turbo Streams broadcasting methods for ActiveRecord models
  # Drop-in replacement for Turbo::Streams::Broadcastable
  module Broadcastable
    extend ActiveSupport::Concern

    # Async broadcast methods (using _later_ suffix for API compatibility)
    def broadcast_replace_later_to(stream_name, **options)
      broadcast_action_later_to(stream_name, action: :replace, **options)
    end

    def broadcast_update_later_to(stream_name, **options)
      broadcast_action_later_to(stream_name, action: :update, **options)
    end

    def broadcast_append_later_to(stream_name, **options)
      broadcast_action_later_to(stream_name, action: :append, **options)
    end

    def broadcast_prepend_later_to(stream_name, **options)
      broadcast_action_later_to(stream_name, action: :prepend, **options)
    end

    # Synchronous broadcast methods (no _later_)
    # Since our HTTP POST is already effectively immediate, these are aliases
    def broadcast_replace_to(stream_name, **options)
      broadcast_action_later_to(stream_name, action: :replace, **options)
    end

    def broadcast_update_to(stream_name, **options)
      broadcast_action_later_to(stream_name, action: :update, **options)
    end

    def broadcast_append_to(stream_name, **options)
      broadcast_action_later_to(stream_name, action: :append, **options)
    end

    def broadcast_prepend_to(stream_name, **options)
      broadcast_action_later_to(stream_name, action: :prepend, **options)
    end

    def broadcast_remove_to(stream_name, target:)
      turbo_stream_html = <<~HTML
        <turbo-stream action="remove" target="#{target}">
        </turbo-stream>
      HTML

      broadcast_turbo_stream(stream_name, turbo_stream_html)
    end

    private

    def broadcast_action_later_to(stream_name, action:, target: nil, partial: nil, html: nil, locals: {})
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
