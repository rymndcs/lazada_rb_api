# frozen_string_literal: true

require "net/http"

module LazadaRbApi
  module Transport
    # The default transport. Any object with this #call signature can replace it (tests use a fake).
    # It opens one connection per request and holds no mutable state, so it is safe to share across threads.
    class NetHttp
      NETWORK_ERRORS = [
        Timeout::Error, SocketError, SystemCallError, IOError, EOFError, OpenSSL::SSL::SSLError,
        Net::HTTPBadResponse, Net::ProtocolError
      ].freeze
      METHODS = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.freeze

      def initialize(open_timeout: 5, read_timeout: 30)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        freeze
      end

      # => { status: Integer, headers: Hash, body: String }. Raises TransportError when no response was read.
      def call(method:, url:, headers:, body:)
        uri = URI(url)
        request = METHODS.fetch(method).new(uri.request_uri, headers)
        request.body = body if body
        response = http_for(uri).start { |http| http.request(request) }
        { status: response.code.to_i, headers: response.each_header.to_h, body: response.body.to_s }
      rescue *NETWORK_ERRORS => e
        raise TransportError, "#{e.class}: #{e.message}"
      end

      private

      def http_for(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout
        http
      end
    end
  end
end
