# frozen_string_literal: true

# Wire-shape tests check several fields of one request, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

# Every signing and push vector in the Lazada plan (§3, §9): the official vector of doc 108069, the ASCII ordering of
# doc 108068, and the push scheme of doc 120168.
class SignerTest < Minitest::Test
  include UnitHelper

  def signer
    LazadaRbApi.const_get(:Signer)
  end

  def test_official_signing_vector
    vector = A.signing_vectors.first

    assert_equal vector[:expected_base_string], vector[:base_string]
    assert_equal "4190D32361CFB9581350222F345CB77F3B19F0E31D162316848A2C1FFD5FAB4A", vector[:signature]
  end

  # https://open.lazada.com/apps/doc/doc?nodeId=10400&docId=108068: "bar=2, foo=1, foo_bar=3, foobar=4", then the
  # API name in front. The doc publishes no digest for this example, so only the base string is checked.
  def test_ascii_ordering_example
    params = { "foo" => "1", "bar" => "2", "foo_bar" => "3", "foobar" => "4" }

    assert_equal "/test/apibar2foo1foo_bar3foobar4", signer.base_string("/test/api", params)
  end

  def test_upper_case_hex_over_utf8_and_empty_values_skipped
    base = signer.base_string("/x", { "b" => "", "a" => "café", "c" => nil })

    assert_equal "/xacafé".b, base
    assert_match(/\A[0-9A-F]{64}\z/, signer.sign("secret", base))
    assert_equal OpenSSL::HMAC.hexdigest("SHA256", "secret", "/xacafé").upcase, signer.sign("secret", base)
  end

  def test_push_vectors
    A.webhook_vectors.each do |vector|
      base = signer.push_base_string(A::APP_KEY, vector[:raw_body])

      assert_equal vector[:signature], signer.push_sign(A::APP_SECRET, base), vector[:name]
    end
  end

  # The push guide's own example (doc 120168): app key 123456, secret 3412gyo124goi3124, and the body printed with its
  # data elided as {...}. The plan (§9) expected it to be unreproducible, but the digest is over that literal text,
  # so the official vector reproduces byte for byte.
  def test_the_official_push_example
    assert LazadaRbApi::Webhook.verify(raw_body: A::GUIDE_PUSH, app_key: "123456", app_secret: "3412gyo124goi3124",
                                       signature: "f3d2ca947f16a50b577c036adecd18bec126ea19cadedd59816e255d3b6104ab")
    assert_equal '{"seller_id":"1234567", "message_type":0, "data":{...}..}', A::GUIDE_PUSH
  end

  def test_get_sends_every_parameter_in_the_query
    request = request_for { |shop| shop.products.get(234_222_211) }

    assert_equal %w[app_key sign_method timestamp access_token item_id sign], request.query_pairs.map(&:first)
    assert_equal "1517820392000", request.query["timestamp"]
    assert_equal "sha256", request.query["sign_method"]
    assert_nil request.body
  end

  def test_post_puts_system_parameters_in_the_query_and_business_parameters_in_the_form_body
    request = request_for { |shop| shop.products.unlist([1]) }

    assert_equal %w[app_key sign_method timestamp access_token sign], request.query_pairs.map(&:first)
    assert_equal "application/x-www-form-urlencoded; charset=UTF-8", request.header("Content-Type")
    assert_equal({ "apiRequestBody" => '{"Request":{"Product":{"ItemId":"1"}}}' }, form(request))
    assert_equal A.expected_signature(request), request.query["sign"]
  end

  def test_the_form_body_is_signed
    first = request_for { |shop| shop.products.update(1, { "Attributes" => { "name" => "A" } }) }
    second = request_for { |shop| shop.products.update(1, { "Attributes" => { "name" => "B" } }) }

    refute_equal first.query["sign"], second.query["sign"]
  end

  def test_the_image_file_part_is_not_signed
    request = request_for(Fixtures.response("image_upload")) do |shop|
      shop.media.upload_image(StringIO.new("img"), filename: "a.png")
    end
    other = request_for(Fixtures.response("image_upload")) do |shop|
      shop.media.upload_image(StringIO.new("another image"), filename: "a.png")
    end

    assert_equal request.query["sign"], other.query["sign"]
    assert_equal A.expected_signature(request), request.query["sign"]
    assert_includes request.body, "Content-Type: image/png\r\n\r\nimg\r\n"
  end

  def test_empty_parameters_are_never_sent
    request = request_for { |shop| shop.categories.recommend(title: "Bulb", image_url: "", note: nil) }

    assert_equal %w[app_key sign_method timestamp access_token product_name sign], request.query_pairs.map(&:first)
  end
end
# rubocop:enable Minitest/MultipleAssertions
