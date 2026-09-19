# frozen_string_literal: true

module LazadaRbApi
  # Stamps, signs, sends, parses and classifies one request. Each retry under an opt-in RetryPolicy goes through
  # #perform again, so it is re-stamped from the injected clock and re-signed.
  #
  # Where the parameters go follows Lazada's official SDK: on GET every parameter is in the query string; on POST the
  # system parameters and `sign` are in the query string and the business parameters are in the form body
  # (multipart when a file is attached). Every parameter except `sign` and the file is signed.
  class Connection
    include Redaction

    HTTP_METHODS = %i[get post].freeze
    NETWORK_ERRORS = Transport::NetHttp::NETWORK_ERRORS
    USER_AGENT = "lazada_rb_api/#{VERSION} (Ruby #{RUBY_VERSION})".freeze
    FORM = "application/x-www-form-urlencoded; charset=UTF-8"

    attr_reader :app_key, :auth_base_url, :endpoint

    def initialize(app_key:, app_secret:, hosts:, endpoint:, transport:, clock:, logger:, retry_policy:)
      @app_key = app_key
      @app_secret = app_secret
      @base_url = hosts.fetch(:api)
      @auth_base_url = hosts.fetch(:auth)
      @token_base_url = hosts.fetch(:token)
      @endpoint = endpoint
      @transport = transport
      @clock = clock
      @logger = logger
      @retry_policy = retry_policy
      freeze
    end

    # The current Time from the injected clock: the only time source for signing and expiries.
    def now
      @clock.call
    end

    # query: parameters for the query string. body: business parameters for the form body (POST only).
    # file: { name:, filename:, io: } for a multipart upload. host: :api, or :token for the token API.
    # Hash and Array values are sent as JSON; nil and empty values are never sent.
    def call(http_method, path, query: nil, body: nil, file: nil, access_token: nil, host: :api, idempotent: nil)
      raise ArgumentError, "unknown HTTP method #{http_method.inspect}; Lazada takes :get or :post" unless
        HTTP_METHODS.include?(http_method)
      raise ArgumentError, "path must start with /" unless path.to_s.start_with?("/")

      idempotent = http_method == :get if idempotent.nil?
      request = { http_method:, path: path.to_s, query: params(query), body: params(body), file:, access_token:,
                  host: }
      @retry_policy.run { perform(request, idempotent) }
    end

    def inspect
      "#<#{self.class.name} app_key=#{@app_key} base_url=#{@base_url} app_secret=#{Redaction::REDACTED}>"
    end

    private

    def perform(request, idempotent)
      time = now
      query, body = split(request)
      system = system_params(time, request[:access_token])
      signature = Signer.sign(@app_secret, Signer.base_string(request[:path], system.merge(query).merge(body)))
      url = "#{host_url(request[:host])}#{request[:path]}?" \
            "#{URI.encode_www_form(system.merge(query).merge("sign" => signature))}"
      payload, content_type = encode_body(request, body)
      headers = { "User-Agent" => USER_AGENT, "Accept" => "application/json" }
      headers["Content-Type"] = content_type if content_type
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = send_request(request[:http_method], url, headers, payload, idempotent)
      log(request, result, started)
      Envelope.build(result, endpoint: request[:path], idempotent:, now: time)
    end

    # On GET there is no body: business parameters join the query.
    def split(request)
      return [request[:query].merge(request[:body]), {}] if request[:http_method] == :get

      [request[:query], request[:body]]
    end

    def system_params(time, access_token)
      system = { "app_key" => @app_key, "sign_method" => "sha256", "timestamp" => (time.to_r * 1000).floor.to_s }
      system["access_token"] = access_token.to_s unless access_token.nil?
      system
    end

    def host_url(host)
      { api: @base_url, token: @token_base_url }.fetch(host)
    end

    def encode_body(request, body)
      return [nil, nil] if request[:http_method] == :get
      return Multipart.build(fields: body, file: request[:file]).reverse if request[:file]

      [URI.encode_www_form(body), FORM]
    end

    def params(hash)
      (hash || {}).each_with_object({}) do |(key, value), out|
        text = case value
               when nil then nil
               when Hash, Array then JSON.generate(value)
               else value.to_s
               end
        out[key.to_s] = text unless text.nil? || text.empty?
      end
    end

    def send_request(http_method, url, headers, body, idempotent)
      @transport.call(method: http_method, url:, headers:, body:)
    rescue TransportError, *NETWORK_ERRORS => e
      raise TransportError.new(e.message, idempotent:)
    end

    def log(request, result, started)
      return unless @logger

      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      request_id = Envelope.parse(result[:body])&.fetch("request_id", nil)
      @logger.debug("lazada_rb_api #{request[:http_method].upcase} #{request[:path]} status=#{result[:status]} " \
                    "request_id=#{request_id} duration_ms=#{ms}")
    end
  end
  private_constant :Connection
end
