# frozen_string_literal: true

# Wire-shape tests check several fields of one request, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"
require "socket"

# The default transport, against a one-shot server on the loopback interface. No external network is touched.
class NetHttpTest < Minitest::Test
  def serve_once(response)
    server = TCPServer.new("127.0.0.1", 0)
    received = +""
    thread = Thread.new do
      socket = server.accept
      received << socket.readpartial(65_536) until received.include?("\r\n\r\n")
      length = received[/^Content-Length: (\d+)/i, 1].to_i
      received << socket.readpartial(65_536) while received.bytesize < received.index("\r\n\r\n") + 4 + length
      socket.write(response)
      socket.close
    end
    yield server.addr[1]
    thread.join(5)
    received
  ensure
    server&.close
  end

  def test_round_trip
    body = "{\"code\":\"0\"}"
    reply = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nX-Test: yes\r\n" \
            "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
    result = nil
    received = serve_once(reply) do |port|
      result = LazadaRbApi::Transport::NetHttp.new.call(method: :post, url: "http://127.0.0.1:#{port}/rest/x?a=1",
                                                        headers: { "Content-Type" => "application/json" },
                                                        body: "{\"k\":1}")
    end

    assert_equal 200, result[:status]
    assert_equal "yes", result[:headers]["x-test"]
    assert_equal body, result[:body]
    assert_match %r{\APOST /rest/x\?a=1 HTTP/1.1}, received
    assert_includes received, "{\"k\":1}"
  end

  def test_connection_refused_is_a_transport_error
    port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }

    assert_raises(LazadaRbApi::TransportError) do
      LazadaRbApi::Transport::NetHttp.new(open_timeout: 1).call(method: :get, url: "http://127.0.0.1:#{port}/",
                                                                headers: {}, body: nil)
    end
  end

  def test_unknown_method
    assert_raises(KeyError) do
      LazadaRbApi::Transport::NetHttp.new.call(method: :patch, url: "http://127.0.0.1:1/", headers: {}, body: nil)
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
