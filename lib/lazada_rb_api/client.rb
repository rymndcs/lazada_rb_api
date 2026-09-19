# frozen_string_literal: true

module LazadaRbApi
  # One Client per app credential (Lazada app_key + app_secret). Immutable and safe to share across threads.
  # There is no global configuration.
  class Client
    include Redaction

    attr_reader :app_key, :endpoint, :auth

    # app_key:        the Lazada app key (String or Integer).
    # app_secret:     the Lazada app secret.
    # endpoint:       a Symbol from LazadaRbApi::ENDPOINTS: the country whose API host to call (:ph, :my, :sg, :th,
    #                 :vn, :id). A token works only on its own country's host.
    # base_url:       any API host URL; overrides the endpoint's API host.
    # auth_base_url:  any consent page host URL; overrides the endpoint's auth host.
    # token_base_url: any token API host URL; overrides the endpoint's token host.
    # transport:      any object with #call(method:, url:, headers:, body:) -> { status:, headers:, body: }.
    # clock:          returns a Time; the only time source for signing and expiries.
    # logger:         any Logger; debug lines only, and never a secret.
    # retry_policy:   RetryPolicy.none (default) or an opt-in RetryPolicy.new(...).
    def initialize(app_key:, app_secret:, endpoint: Endpoints::DEFAULT, base_url: nil, auth_base_url: nil,
                   token_base_url: nil, transport: Transport::NetHttp.new, clock: -> { Time.now }, logger: nil,
                   retry_policy: RetryPolicy.none)
      @app_key = app_key!(app_key)
      @endpoint = endpoint
      named = hosts!(endpoint)
      hosts = { api: url!(base_url || named[:api], "base_url"),
                auth: url!(auth_base_url || named[:auth], "auth_base_url"),
                token: url!(token_base_url || named[:token], "token_base_url") }
      @connection = Connection.new(app_key: @app_key, app_secret: secret!(app_secret), hosts:, endpoint:,
                                   transport: callable!(transport, "transport"), clock: callable!(clock, "clock"),
                                   logger:, retry_policy: retry_policy || RetryPolicy.none)
      @auth = Auth.new(@connection)
      freeze
    end

    # A shop session. Lazada's locator is empty: the token alone names the store.
    def shop(access_token:, **locator)
      unknown = locator.keys - Shop::LOCATOR_KEYS
      raise ArgumentError, "unknown locator key(s) #{unknown.inspect}: a Lazada token is one store" if unknown.any?

      Shop.new(@connection, access_token:)
    end

    # GET /seller/get with the token: the one store this token reaches, as a single-page Pager of AuthorizedShop.
    # region is the configured endpoint's country; Lazada documents no authorization deadline here (the token
    # expiries are on the Grant).
    # https://open.lazada.com/apps/doc/api?path=/seller/get
    def authorized_shops(access_token: nil)
      raise ArgumentError, "access_token: is required: Lazada lists the store a token belongs to" if access_token.nil?

      Pager.new do
        response = @connection.call(:get, Endpoints::SELLER, access_token: access_token.to_s)
        data = response.data.is_a?(Hash) ? response.data : {}
        Page.new(items: [authorized_shop(data)].freeze, next_cursor: nil, total: 1, response:)
      end
    end

    # Verifies a Lazada push with this client's app key and secret, then parses it. url: is ignored (Lazada does not
    # sign it). Raises WebhookSignatureError when verification fails.
    def verify_webhook(raw_body:, signature:, url: nil)
      valid = Webhook.verify(raw_body:, signature:, app_key: @app_key, app_secret: @app_secret, url:)
      raise WebhookSignatureError, "Lazada push signature did not verify" unless valid

      Webhook.parse(raw_body)
    end

    # The escape hatch for app-level paths, signed without an access token (for example the no-authorization
    # catalogue endpoints). On POST, body: goes in the form body. One call, one request.
    def request(http_method, path, query: nil, body: nil, idempotent: nil)
      @connection.call(http_method, path, query:, body:, idempotent:)
    end

    def inspect
      "#<#{self.class.name} app_key=#{@app_key.inspect} endpoint=#{@endpoint.inspect} " \
        "app_secret=#{Redaction::REDACTED}>"
    end

    private

    def authorized_shop(data)
      AuthorizedShop.new(shop_id: data["seller_id"].to_s, name: data["name"]&.to_s, region: @endpoint.to_s.upcase,
                         authorization_expires_at: nil, locator: {}.freeze, raw: data)
    end

    def app_key!(value)
      key = value.to_s
      raise ConfigurationError, "app_key must be a non-empty String or Integer" if key.empty?

      key
    end

    def secret!(value)
      raise ConfigurationError, "app_secret must be a non-empty String" unless value.is_a?(String) && !value.empty?

      @app_secret = value
    end

    def hosts!(endpoint)
      ENDPOINTS.fetch(endpoint) do
        raise ConfigurationError, "unknown endpoint #{endpoint.inspect}; expected one of #{ENDPOINTS.keys.inspect} " \
                                  "(or pass base_url: / auth_base_url: / token_base_url:)"
      end
    end

    def url!(value, name)
      uri = URI.parse(value.to_s)
      raise ConfigurationError, "#{name} must be an http(s) URL" unless %w[http https].include?(uri.scheme) && uri.host

      value.to_s.chomp("/")
    rescue URI::InvalidURIError
      raise ConfigurationError, "#{name} must be an http(s) URL"
    end

    def callable!(value, name)
      raise ConfigurationError, "#{name} must respond to #call" unless value.respond_to?(:call)

      value
    end
  end
end
