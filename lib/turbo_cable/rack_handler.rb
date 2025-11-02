require 'digest/sha1'
require 'base64'
require 'json'

module TurboCable
  # Rack middleware for handling WebSocket connections using Rack hijack
  # Uses RFC 6455 WebSocket protocol (no dependencies required)
  class RackHandler
    GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    def initialize(app)
      @app = app
      @connections = {} # stream => [sockets]
      @mutex = Mutex.new
    end

    def call(env)
      # Handle WebSocket upgrade for /cable
      if env['PATH_INFO'] == '/cable' && websocket_request?(env)
        handle_websocket(env)
        # Return -1 to indicate we've hijacked the connection
        [-1, {}, []]
      elsif env['PATH_INFO'] == '/_broadcast' && env['REQUEST_METHOD'] == 'POST'
        handle_broadcast(env)
      else
        @app.call(env)
      end
    end

    private

    def websocket_request?(env)
      env['HTTP_UPGRADE']&.downcase == 'websocket' &&
        env['HTTP_CONNECTION']&.downcase&.include?('upgrade')
    end

    def handle_websocket(env)
      # Hijack the TCP socket from Rack/Puma
      io = env['rack.hijack'].call

      # Perform WebSocket handshake (RFC 6455)
      key = env['HTTP_SEC_WEBSOCKET_KEY']
      accept = Base64.strict_encode64(Digest::SHA1.digest(key + GUID))

      io.write("HTTP/1.1 101 Switching Protocols\r\n")
      io.write("Upgrade: websocket\r\n")
      io.write("Connection: Upgrade\r\n")
      io.write("Sec-WebSocket-Accept: #{accept}\r\n")
      io.write("\r\n")

      # Track connection subscriptions
      subscriptions = Set.new

      # Handle WebSocket frames in a thread
      Thread.new do
        begin
          loop do
            frame = read_frame(io)
            break if frame.nil? || frame[:opcode] == 8 # Close frame

            if frame[:opcode] == 1 # Text frame
              handle_message(io, frame[:payload], subscriptions)
            elsif frame[:opcode] == 9 # Ping
              send_frame(io, 10, frame[:payload]) # Pong
            end
          end
        rescue => e
          Rails.logger.error("WebSocket error: #{e}")
        ensure
          # Unsubscribe from all streams
          @mutex.synchronize do
            subscriptions.each do |stream|
              @connections[stream]&.delete(io)
              @connections.delete(stream) if @connections[stream]&.empty?
            end
          end
          io.close rescue nil
        end
      end
    end

    def handle_message(io, payload, subscriptions)
      msg = JSON.parse(payload)

      case msg['type']
      when 'subscribe'
        stream = msg['stream']

        # Add connection to stream
        @mutex.synchronize do
          @connections[stream] ||= []
          @connections[stream] << io
        end
        subscriptions.add(stream)

        # Send confirmation
        response = { type: 'subscribed', stream: stream }
        send_frame(io, 1, response.to_json)

      when 'unsubscribe'
        stream = msg['stream']

        # Remove connection from stream
        @mutex.synchronize do
          @connections[stream]&.delete(io)
          @connections.delete(stream) if @connections[stream]&.empty?
        end
        subscriptions.delete(stream)

      when 'pong'
        # Client responding to ping
      end
    end

    def handle_broadcast(env)
      # Security: Only allow broadcasts from localhost
      unless localhost_request?(env)
        return [403, { 'Content-Type' => 'text/plain' }, ['Forbidden: Broadcasts only allowed from localhost']]
      end

      # Read JSON body
      input = env['rack.input'].read
      data = JSON.parse(input)

      stream = data['stream']
      message = { type: 'message', stream: stream, data: data['data'] }
      payload = message.to_json

      # Broadcast to all connections on this stream
      sockets = @mutex.synchronize { @connections[stream]&.dup || [] }

      sockets.each do |io|
        begin
          send_frame(io, 1, payload)
        rescue
          # Connection died, will be cleaned up by read loop
        end
      end

      [200, { 'Content-Type' => 'text/plain' }, ['OK']]
    end

    def localhost_request?(env)
      remote_addr = env['REMOTE_ADDR']
      # Allow IPv4 localhost (127.0.0.1, 127.x.x.x) and IPv6 localhost (::1)
      remote_addr =~ /^127\./ || remote_addr == '::1'
    end

    # Read WebSocket frame (RFC 6455 format)
    def read_frame(io)
      byte1 = io.read(1)&.unpack1('C')
      return nil if byte1.nil?

      fin = (byte1 & 0x80) != 0
      opcode = byte1 & 0x0F

      byte2 = io.read(1)&.unpack1('C')
      return nil if byte2.nil?

      masked = (byte2 & 0x80) != 0
      length = byte2 & 0x7F

      if length == 126
        length = io.read(2).unpack1('n')
      elsif length == 127
        length = io.read(8).unpack1('Q>')
      end

      mask_key = masked ? io.read(4).unpack('C*') : nil
      payload_data = io.read(length)

      if masked && mask_key
        payload_data = payload_data.bytes.map.with_index do |byte, i|
          byte ^ mask_key[i % 4]
        end.pack('C*')
      end

      { opcode: opcode, payload: payload_data, fin: fin }
    end

    # Send WebSocket frame (RFC 6455 format)
    def send_frame(io, opcode, payload)
      payload = payload.b
      length = payload.bytesize

      frame = [0x80 | opcode].pack('C') # FIN=1

      if length < 126
        frame << [length].pack('C')
      elsif length < 65536
        frame << [126, length].pack('Cn')
      else
        frame << [127, length].pack('CQ>')
      end

      frame << payload
      io.write(frame)
    end
  end
end
