# frozen_string_literal: true

module LazadaRbApi
  # Seller authorization and tokens (https://open.lazada.com/apps/doc/doc?nodeId=10450&docId=108260).
  #
  # The gem stores no tokens and never refreshes on its own. Lazada returns a new refresh token on every refresh and
  # does not say whether the old one survives: persist both tokens of the returned Grant in one write before doing
  # anything else. Lifetimes are whatever Lazada returns; the official documents disagree (10 d / 50 d in the
  # authorization guide, 30 d / 180 d for Online apps in the FAQ), so none is hard-coded.
  class Auth
    include Redaction

    def initialize(connection)
      @connection = connection
      freeze
    end

    # => the seller consent link on the configured auth host:
    #    <auth host>/oauth/authorize?response_type=code&force_auth=true&redirect_uri=..&client_id=..[&state=..]
    # redirect_uri must match the callback URL configured on the app. Lazada redirects back with code (valid 30
    # minutes, single use) and state.
    def authorize_url(redirect_uri: nil, state: nil)
      raise ArgumentError, "redirect_uri: is required" if redirect_uri.to_s.empty?

      query = { response_type: "code", force_auth: "true", redirect_uri: redirect_uri.to_s,
                client_id: @connection.app_key }
      query[:state] = state.to_s unless state.nil?
      "#{@connection.auth_base_url}#{Endpoints::AUTHORIZE_PAGE}?#{URI.encode_www_form(query)}"
    end

    # POST /auth/token/create on the token host, signed without an access token. No locator: one code is one store.
    # https://open.lazada.com/apps/doc/api?path=/auth/token/create
    def exchange_code(code:, **locator)
      raise ArgumentError, "code: is empty" if code.to_s.empty?

      no_locator!(locator)
      grant(@connection.call(:post, Endpoints::TOKEN_CREATE, body: { code: code.to_s }, host: :token))
    end

    # POST /auth/token/refresh on the token host. Returns a NEW refresh token. No locator.
    # https://open.lazada.com/apps/doc/api?path=/auth/token/refresh
    def refresh(refresh_token:, **locator)
      raise ArgumentError, "refresh_token: is empty" if refresh_token.to_s.empty?

      no_locator!(locator)
      grant(@connection.call(:post, Endpoints::TOKEN_REFRESH, body: { refresh_token: refresh_token.to_s },
                                                              host: :token))
    end

    def inspect
      "#<#{self.class.name}>"
    end

    private

    def no_locator!(locator)
      return if locator.empty?

      raise ArgumentError, "unknown locator key(s) #{locator.keys.inspect}: a Lazada token is one store"
    end

    # expires_in and refresh_expires_in are seconds from now, sent as a Number or a String depending on the
    # endpoint. The store list is country_user_info (create) or country_user_info_list (refresh).
    def grant(response)
      data = response.data
      now = @connection.now
      Grant.new(access_token: data["access_token"].to_s, refresh_token: data["refresh_token"].to_s,
                access_token_expires_at: expiry(now, data["expires_in"]),
                refresh_token_expires_at: expiry(now, data["refresh_expires_in"]),
                shop_ids: shop_ids(data), raw: response.raw)
    end

    def expiry(now, seconds)
      value = Integer(seconds.to_s, 10, exception: false)
      value.nil? ? nil : (now + value).utc
    end

    def shop_ids(data)
      list = data["country_user_info"] || data["country_user_info_list"]
      Array(list).grep(Hash).map { |info| info["seller_id"].to_s }.reject(&:empty?).uniq.freeze
    end
  end
end
