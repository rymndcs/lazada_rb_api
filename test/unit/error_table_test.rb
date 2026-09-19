# frozen_string_literal: true

# Wire-shape tests check several fields of one request, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

class ErrorTableTest < Minitest::Test
  include UnitHelper

  def classify(code, message, detail = [])
    LazadaRbApi.const_get(:ErrorTable).classify(code, message, detail)
  end

  def raise_on_info(response)
    client, = client_with(response)
    assert_raises(LazadaRbApi::Error) { A.build_shop(client).info }
  end

  # test/fixtures/error_list.json holds every (code, message) pair in the error tables of the endpoints the gem
  # calls, plus the FAQ's rate-limit and seller-state codes. Re-pull it to detect drift in the docs.
  def test_every_documented_pair_maps_to_a_documented_class
    pairs = Fixtures.load("error_list")["pairs"]

    assert_operator pairs.size, :>, 150
    unmapped = pairs.select { |pair| classify(pair["code"], pair["message"]) == LazadaRbApi::ApiError }

    assert_empty(unmapped.map { |pair| "#{pair["code"]}: #{pair["message"]}" })
  end

  def test_overview_codes_with_detail_are_business_rejections
    detail = [{ "field" => "SellerSku", "message" => "SellerSku repeat" }]

    %w[500 501 503].each do |code|
      assert_equal LazadaRbApi::ServerError, classify(code, "Update product failed")
      assert_equal LazadaRbApi::BusinessError, classify(code, "Update product failed", detail)
    end
  end

  def test_overloaded_and_message_classified_codes
    assert_equal LazadaRbApi::ServerError, classify("6", "E006: Unexpected internal error")
    assert_equal LazadaRbApi::RequestError, classify("6", "Invalid status filter")
    assert_equal LazadaRbApi::SignatureError, classify("MissingParameter", "the input parameter “sign” that is " \
                                                                           "mandatory for processing this request")
    assert_equal LazadaRbApi::RequestError, classify("MissingParameter", "the input parameter “order_id” is missing")
    assert_equal LazadaRbApi::PermissionError, classify("E501", "SELLER_NOT_PERMITTED")
  end

  def test_families
    assert_equal LazadaRbApi::AuthenticationError, classify("IllegalAccessToken", "invalid or expired")
    assert_equal LazadaRbApi::SignatureError, classify("IncompleteSignature", "does not conform")
    assert_equal LazadaRbApi::PermissionError, classify("SellerNotVerified", "Seller not verified")
    assert_equal LazadaRbApi::PermissionError, classify("ONLY_CB_SELLER_SUPPORTED", "For now, only cb seller")
    assert_equal LazadaRbApi::RateLimitError, classify("AppApiCallLimit", "App-level rate limit")
    assert_equal LazadaRbApi::RateLimitError, classify("4154", "SYS_REQUEST_TOO_FAST")
    assert_equal LazadaRbApi::ConcurrencyError, classify("4147", "Concurrent product edit is not allowed")
    assert_equal LazadaRbApi::BusinessError, classify("4163", "BIZ_CHECK_RESTRICTED_CATEGORY")
    assert_equal LazadaRbApi::BusinessError, classify("4155", "Update product failed")
    assert_equal LazadaRbApi::ApiError, classify("SomethingNew", "never documented")
  end

  def test_error_envelope_fields_and_detail
    detail = [{ "field" => "SellerSku", "message" => "SellerSku repeat" }]
    error = raise_on_info(A.error("501", "Update product failed", detail:, status: 400))

    assert_instance_of LazadaRbApi::BusinessError, error
    assert_equal "501", error.code
    assert_equal detail, error.detail
    assert_equal 400, error.http_status
    assert_equal "/seller/get", error.endpoint
    assert_equal "Update product failed", error.message
    refute_predicate error, :retryable?
  end

  def test_901_asks_for_the_next_second
    error = raise_on_info(A.rate_limit_response)

    assert_in_delta 1.0, error.retry_after
    assert_nil raise_on_info(A.error("ApiCallLimit", "API-level global rate limit")).retry_after
  end

  def test_retry_after_accepts_an_http_date
    date = (A.fixed_time + 30).httpdate
    error = raise_on_info(FakeTransport.json("", status: 503, headers: { "retry-after" => date }))

    assert_instance_of LazadaRbApi::ServerError, error
    assert_in_delta 30.0, error.retry_after
  end

  def test_success_false_envelopes_raise
    brands = { "success" => false, "error_code" => "SYS_ERROR", "error_msg" => "inner service fail",
               "request_id" => "r" }
    limit = { "success" => "false", "errorCodes" => ["ONLY_CB_SELLER_SUPPORTED"],
              "errorMsgs" => ["For now, only cb seller supported"], "request_id" => "r" }

    assert_instance_of LazadaRbApi::ServerError, raise_on_info(FakeTransport.json(brands))
    error = raise_on_info(FakeTransport.json(limit))

    assert_instance_of LazadaRbApi::PermissionError, error
    assert_equal "ONLY_CB_SELLER_SUPPORTED", error.code
  end

  def test_success_true_with_a_stale_error_code_is_a_success
    shop, = shop_with(Fixtures.response("product_global_update_status"))

    assert_equal "E0019", shop.products.relist([1]).raw["error_code"]
  end

  def test_a_null_or_absent_payload_is_an_empty_hash
    [{ "code" => "0", "request_id" => "r", "data" => nil }, { "code" => "0", "request_id" => "r" }].each do |body|
      shop, = shop_with(FakeTransport.json(body))
      data = shop.products.unlist([1]).data

      assert_empty(data)
      assert_predicate data, :frozen?
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
