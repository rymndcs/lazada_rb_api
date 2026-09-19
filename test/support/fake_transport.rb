# frozen_string_literal: true

require "json"
require "uri"

# A transport that never touches the network. Shared verbatim by the three sibling gems (listed in
# test/conformance/MANIFEST). It records every request and answers from a queue or a router block.
#
#   transport = FakeTransport.new(FakeTransport.json({ "error" => "" }))
#   transport = FakeTransport.new { |request| FakeTransport.json(...) }
#   FakeTransport.new(ShopeeRbApi::TransportError.new("timeout"))   # an Exception in the queue is raised
class FakeTransport
  Request = Data.define(:http_method, :url, :headers, :body) do
    def uri
      URI(url)
    end

    def path
      uri.path
    end

    # => Array of [key, value] pairs, in order, repeated keys kept.
    def query_pairs
      URI.decode_www_form(uri.query.to_s)
    end

    # => { key => value } or { key => [values] } for repeated keys.
    def query
      query_pairs.group_by(&:first).transform_values { |pairs| pairs.size == 1 ? pairs.first.last : pairs.map(&:last) }
    end

    def header(name)
      headers.find { |key, _| key.to_s.casecmp?(name) }&.last
    end

    def json
      JSON.parse(body)
    end
  end

  attr_reader :requests

  def self.json(body, status: 200, headers: {})
    { status:, headers:, body: body.is_a?(String) ? body : JSON.generate(body) }
  end

  def initialize(*responses, &router)
    @responses = responses
    @router = router
    @requests = []
  end

  def push(*responses)
    @responses.concat(responses)
    self
  end

  def call(method:, url:, headers:, body:)
    request = Request.new(http_method: method, url:, headers: headers.dup.freeze, body: body&.dup)
    @requests << request
    response = @router ? @router.call(request) : @responses.shift
    raise "FakeTransport: no response queued for #{method.to_s.upcase} #{request.path}" if response.nil?
    raise response if response.is_a?(Exception)

    response
  end
end
