module TurboCable
  module StreamsHelper
    # Custom turbo_stream_from that works with our WebSocket implementation
    # Drop-in replacement for Turbo Stream's turbo_stream_from helper
    def turbo_stream_from(*stream_names)
      streams_str = stream_names.join(",")
      Rails.logger.debug "[TurboCable] turbo_stream_from rendering marker for streams: #{streams_str}"

      # Create a marker element that JavaScript will find and subscribe to
      tag.div(
        data: {
          turbo_stream: true,
          streams: streams_str
        },
        style: "display: none;"
      )
    end
  end
end
