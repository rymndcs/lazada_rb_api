# frozen_string_literal: true

# Wire-shape tests check several fields of one request, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

class AuthTest < Minitest::Test
  include UnitHelper

  def test_authorize_url_follows_the_authorization_guide
    client, = client_with
    url = client.auth.authorize_url(redirect_uri: "https://wms.example/cb?x=1", state: "s 1")

    assert_equal "https://auth.lazada.com/oauth/authorize?response_type=code&force_auth=true&" \
                 "redirect_uri=https%3A%2F%2Fwms.example%2Fcb%3Fx%3D1&client_id=123456&state=s+1", url
    assert_raises(ArgumentError) { client.auth.authorize_url }
    refute_includes client.auth.authorize_url(redirect_uri: "https://x.test"), "state="
  end

  def test_exchange_code_is_signed_without_a_token_and_sends_the_code_in_the_body
    client, transport = client_with(Fixtures.response("auth_token_create"))
    grant = client.auth.exchange_code(code: "0_100132_abc")
    request = transport.requests.first

    assert_equal :post, request.http_method
    assert_equal "/rest/auth/token/create", request.path
    assert_nil request.query["access_token"]
    assert_equal({ "code" => "0_100132_abc" }, form(request))
    assert_equal A.expected_signature(request), request.query["sign"]
    assert_equal ["1001"], grant.shop_ids
  end

  def test_refresh_reads_country_user_info_list_and_string_lifetimes
    client, transport = client_with(Fixtures.response("auth_token_refresh"))
    grant = client.auth.refresh(refresh_token: "r")

    assert_equal "/rest/auth/token/refresh", transport.requests.first.path
    assert_equal({ "refresh_token" => "r" }, form(transport.requests.first))
    assert_equal A.fixed_time + 10, grant.access_token_expires_at
    assert_equal A.fixed_time + 60, grant.refresh_token_expires_at
    assert_equal ["1001"], grant.shop_ids
  end

  # The authorization guide documents numeric lifetimes (864000 / 4320000 seconds); the reference samples send
  # strings. Both are read, and nothing is hard-coded when a lifetime is missing.
  def test_numeric_lifetimes_and_a_missing_refresh_lifetime
    body = Fixtures.body("auth_token_create").merge("expires_in" => 864_000).except("refresh_expires_in")
    client, = client_with(FakeTransport.json(body))
    grant = client.auth.exchange_code(code: "c")

    assert_equal A.fixed_time + 864_000, grant.access_token_expires_at
    assert_nil grant.refresh_token_expires_at
  end

  def test_no_locator_and_no_empty_arguments
    client, transport = client_with

    assert_raises(ArgumentError) { client.auth.exchange_code(code: "c", seller_id: 1) }
    assert_raises(ArgumentError) { client.auth.refresh(refresh_token: "r", seller_id: 1) }
    assert_raises(ArgumentError) { client.auth.exchange_code(code: "") }
    assert_raises(ArgumentError) { client.auth.refresh(refresh_token: "") }
    assert_empty transport.requests
  end

  def test_token_errors_are_classified
    client, = client_with(A.error("IllegalRefreshToken", "The specified refresh token is invalid or expired"),
                          A.error("InvalidCode", "Invalid authorization code"),
                          A.error("AUTH_TYPE_UNSUPPORTED", "appkey can only be authorized by market, not support " \
                                                           "refresh"))

    assert_raises(LazadaRbApi::AuthenticationError) { client.auth.refresh(refresh_token: "r") }
    assert_raises(LazadaRbApi::AuthenticationError) { client.auth.exchange_code(code: "c") }
    assert_raises(LazadaRbApi::PermissionError) { client.auth.refresh(refresh_token: "r") }
  end

  def test_authorized_shops_is_the_one_store_of_the_token
    client, transport = client_with(Fixtures.response("seller_get"), endpoint: :sg)
    shops = client.authorized_shops(access_token: "tok").to_a

    assert_equal 1, transport.requests.size
    assert_equal "tok", transport.requests.first.query["access_token"]
    ref = shops.first

    assert_equal "10", ref.shop_id
    assert_equal "abc shop", ref.name
    assert_equal "SG", ref.region
    assert_nil ref.authorization_expires_at
    assert_empty ref.locator
    assert_raises(ArgumentError) { client.authorized_shops }
  end

  def test_shop_takes_no_locator_and_needs_a_token
    client, = client_with

    assert_raises(ArgumentError) { client.shop(access_token: "t", seller_id: 1) }
    assert_raises(ArgumentError) { client.shop(access_token: "") }
    assert_empty client.shop(access_token: "t").locator
  end
end
# rubocop:enable Minitest/MultipleAssertions
