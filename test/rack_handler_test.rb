require "test_helper"
require "turbo_cable/rack_handler"

class RackHandlerTest < ActiveSupport::TestCase
  def setup
    @app = ->(env) { [ 200, {}, [ "OK" ] ] }
    @handler = TurboCable::RackHandler.new(@app)
  end

  test "allows broadcast from localhost IPv4" do
    env = build_broadcast_env("127.0.0.1")
    status, headers, body = @handler.call(env)

    assert_equal 200, status
    assert_equal "OK", body.join
  end

  test "allows broadcast from localhost IPv4 loopback range" do
    env = build_broadcast_env("127.0.0.2")
    status, headers, body = @handler.call(env)

    assert_equal 200, status
    assert_equal "OK", body.join
  end

  test "allows broadcast from localhost IPv6" do
    env = build_broadcast_env("::1")
    status, headers, body = @handler.call(env)

    assert_equal 200, status
    assert_equal "OK", body.join
  end

  test "rejects broadcast from external IPv4" do
    env = build_broadcast_env("192.168.1.1")
    status, headers, body = @handler.call(env)

    assert_equal 403, status
    assert_includes body.join, "Forbidden"
  end

  test "rejects broadcast from external IPv6" do
    env = build_broadcast_env("2001:db8::1")
    status, headers, body = @handler.call(env)

    assert_equal 403, status
    assert_includes body.join, "Forbidden"
  end

  test "rejects broadcast from public IP" do
    env = build_broadcast_env("8.8.8.8")
    status, headers, body = @handler.call(env)

    assert_equal 403, status
    assert_includes body.join, "Forbidden"
  end

  test "accepts JSON broadcast data" do
    json_data = { status: "processing", progress: 50, message: "Test" }
    env = build_broadcast_env("127.0.0.1", json_data)
    status, headers, body = @handler.call(env)

    assert_equal 200, status
    assert_equal "OK", body.join
  end

  test "accepts both HTML string and JSON object broadcasts" do
    # Test HTML string
    html_env = build_broadcast_env("127.0.0.1", "<turbo-stream></turbo-stream>")
    status, _, _ = @handler.call(html_env)
    assert_equal 200, status

    # Test JSON object
    json_env = build_broadcast_env("127.0.0.1", { data: "test" })
    status, _, _ = @handler.call(json_env)
    assert_equal 200, status
  end

  private

  def build_broadcast_env(remote_addr, data = "<turbo-stream></turbo-stream>")
    {
      "PATH_INFO" => "/_broadcast",
      "REQUEST_METHOD" => "POST",
      "REMOTE_ADDR" => remote_addr,
      "rack.input" => StringIO.new(JSON.generate({ stream: "test", data: data }))
    }
  end
end
