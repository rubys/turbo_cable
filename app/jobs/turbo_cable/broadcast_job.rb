module TurboCable
  class BroadcastJob < ApplicationJob
    queue_as :default

    def perform(stream_name, action:, model_gid: nil, target: nil, partial: nil, html: nil, locals: {})
      # Resolve model from GlobalID if provided
      model = GlobalID::Locator.locate(model_gid) if model_gid

      # Determine target
      target ||= "#{model.class.name.underscore}_#{model.id}" if model

      # Generate content HTML
      content_html = if html
        html
      elsif partial
        # Render partial with locals
        ApplicationController.render(partial: partial, locals: locals.merge(model ? { model.class.name.underscore.to_sym => model } : {}))
      elsif model
        # Render default partial for this model
        ApplicationController.render(partial: model, locals: locals)
      else
        raise ArgumentError, "Must provide html, partial, or model"
      end

      # Generate Turbo Stream HTML
      turbo_stream_html = if action.to_sym == :remove
        <<~HTML
          <turbo-stream action="remove" target="#{target}">
          </turbo-stream>
        HTML
      else
        <<~HTML
          <turbo-stream action="#{action}" target="#{target}">
            <template>
              #{content_html}
            </template>
          </turbo-stream>
        HTML
      end

      # Broadcast via HTTP POST
      broadcast_turbo_stream(stream_name, turbo_stream_html)
    end

    private

    def broadcast_turbo_stream(stream_name, html)
      require "net/http"
      require "json"

      # Get the actual Puma/Rails server port from the TURBO_CABLE_PORT env var
      # Don't use ENV['PORT'] as it may be the Thruster/proxy port
      default_port = ENV.fetch('TURBO_CABLE_PORT', '3000')
      uri = URI(ENV.fetch("TURBO_CABLE_BROADCAST_URL", "http://localhost:#{default_port}/_broadcast"))
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 1
      http.read_timeout = 1

      request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
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
