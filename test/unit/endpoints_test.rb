# frozen_string_literal: true

# Wire-shape tests check several fields of one request, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

class EndpointsTest < Minitest::Test
  include UnitHelper

  # https://open.lazada.com/apps/doc/doc?nodeId=10400&docId=108065 and the "Service Endpoints" table of every API
  # page (API hosts); /auth/token/create and the authorization guide, doc 108260 (token and consent hosts). Pulled
  # 2026-09-20.
  DOCUMENTED = {
    ph: "https://api.lazada.com.ph/rest", my: "https://api.lazada.com.my/rest", sg: "https://api.lazada.sg/rest",
    th: "https://api.lazada.co.th/rest", vn: "https://api.lazada.vn/rest", id: "https://api.lazada.co.id/rest"
  }.freeze
  AUTH = "https://auth.lazada.com"
  TOKEN = "https://auth.lazada.com/rest"

  def test_the_named_hosts_are_the_documented_ones
    assert_equal DOCUMENTED.keys, LazadaRbApi::ENDPOINTS.keys
    DOCUMENTED.each { |name, api| assert_equal({ api:, auth: AUTH, token: TOKEN }, LazadaRbApi::ENDPOINTS[name]) }
  end

  def test_default_endpoint_is_ph
    client, = client_with

    assert_equal :ph, client.endpoint
  end

  def test_selecting_each_named_host_sends_every_call_to_its_host
    DOCUMENTED.each do |name, api|
      client, transport = client_with(A.read_success_response, Fixtures.response("auth_token_create"), endpoint: name)
      A.build_shop(client).info
      client.auth.exchange_code(code: "c")

      assert_equal "#{api}/seller/get", transport.requests[0].url.split("?").first, name.to_s
      assert_equal "#{TOKEN}/auth/token/create", transport.requests[1].url.split("?").first, name.to_s
      assert client.auth.authorize_url(redirect_uri: "https://x.test/cb").start_with?("#{AUTH}/oauth/authorize?")
    end
  end

  def test_custom_api_consent_and_token_urls
    client, transport = client_with(A.read_success_response, Fixtures.response("auth_token_refresh"),
                                    endpoint: :my, base_url: "https://lazada-proxy.internal:8443/rest/",
                                    auth_base_url: "https://consent.example.test",
                                    token_base_url: "https://token.example.test/rest")
    A.build_shop(client).info
    client.auth.refresh(refresh_token: "r")

    assert_equal "https://lazada-proxy.internal:8443/rest/seller/get", transport.requests[0].url.split("?").first
    assert_equal "https://token.example.test/rest/auth/token/refresh", transport.requests[1].url.split("?").first
    assert client.auth.authorize_url(redirect_uri: "https://x.test/cb")
                 .start_with?("https://consent.example.test/oauth/authorize?")
    assert_equal :my, client.endpoint
    assert_equal "https://token.example.test/rest", client.token_base_url
  end

  def test_base_url_alone_keeps_the_endpoints_consent_and_token_hosts
    client, transport = client_with(Fixtures.response("auth_token_create"), base_url: "https://api.example.test")
    client.auth.exchange_code(code: "c")

    assert client.auth.authorize_url(redirect_uri: "https://x.test/cb").start_with?("#{AUTH}/oauth/authorize?")
    assert_equal "auth.lazada.com", transport.requests.first.uri.host
  end

  def test_unknown_endpoint_and_bad_token_url
    error = assert_raises(LazadaRbApi::ConfigurationError) { client_with(endpoint: :cn) }

    assert_includes error.message, ":vn"
    assert_raises(LazadaRbApi::ConfigurationError) { client_with(token_base_url: "auth.lazada.com/rest") }
  end

  def test_app_key_and_secret
    assert_raises(LazadaRbApi::ConfigurationError) do
      LazadaRbApi::Client.new(app_key: "", app_secret: "s", transport: FakeTransport.new)
    end
    assert_raises(LazadaRbApi::ConfigurationError) do
      LazadaRbApi::Client.new(app_key: 1, app_secret: "", transport: FakeTransport.new)
    end
    assert_raises(LazadaRbApi::ConfigurationError) do
      LazadaRbApi::Client.new(app_key: 1, app_secret: "s", transport: Object.new)
    end
    assert_equal "123456", LazadaRbApi::Client.new(app_key: 123_456, app_secret: "s").app_key
  end
end
# rubocop:enable Minitest/MultipleAssertions
