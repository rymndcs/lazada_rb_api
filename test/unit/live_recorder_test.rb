# frozen_string_literal: true

# One recording, several properties of the written fixture.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"
require_relative "../live/live_helper"
require "tmpdir"

# The live recorder, offline: it must write a redacted fixture that names its source.
class LiveRecorderTest < Minitest::Test
  def test_records_a_redacted_fixture_naming_its_source
    Dir.mktmpdir do |dir|
      body = { "code" => "0", "request_id" => "r", "access_token" => "tok-123",
               "data" => { "note" => "k=sekret", "email" => "seller@example.test" } }
      inner = FakeTransport.new(FakeTransport.json(body))
      recorder = LiveHelper::Recorder.new(inner, secrets: %w[sekret], label: "ph", dir:)
      recorder.call(method: :get, url: "https://h.test/rest/seller/get?sign=ABC", headers: {}, body: nil)
      text = File.read(File.join(dir, "seller_get.json"))
      fixture = JSON.parse(text)

      assert_match(/\Arecorded live \d{4}-\d{2}-\d{2} \(ph\), redacted\z/, fixture["_source"]["origin"])
      assert_equal "https://open.lazada.com/apps/doc/api?path=/seller/get", fixture["_source"]["url"]
      assert_equal "[REDACTED]", fixture["body"]["access_token"]
      assert_equal "[REDACTED]", fixture["body"]["data"]["email"]
      assert_equal "k=[REDACTED]", fixture["body"]["data"]["note"]
      refute_includes text, "ABC"
    end
  end

  # Captain decision 2026-09-20: order responses carry real customers' data, so they are never written, even when
  # they succeed. Orders stay on documentation samples.
  def test_order_responses_are_never_recorded
    Dir.mktmpdir do |dir|
      responses = %w[orders_get order_get order_items_get].map { |name| Fixtures.response(name) }
      recorder = LiveHelper::Recorder.new(FakeTransport.new(*responses), secrets: [], label: "ph", dir:)
      %w[/rest/orders/get /rest/order/get /rest/order/items/get].each do |path|
        recorder.call(method: :get, url: "https://h.test#{path}?order_id=1", headers: {}, body: nil)
      end

      assert_empty Dir.children(dir)
    end
  end

  def test_customer_personal_data_is_redacted_in_other_responses
    Dir.mktmpdir do |dir|
      data = { "seller_id" => "10", "Email" => "a@b.test", "phone2" => "61****7", "customer_first_name" => "Ha",
               "nickName" => "hh", "address1" => "1 Changi Village Road", "addressDetail" => { "city" => "SG" },
               "recipient_info" => { "identify_no" => "012345679" }, "buyer" => ["x"], "status" => "ACTIVE" }
      inner = FakeTransport.new(FakeTransport.json({ "code" => "0", "request_id" => "r", "data" => data }))
      recorder = LiveHelper::Recorder.new(inner, secrets: [], label: "ph", dir:)
      recorder.call(method: :get, url: "https://h.test/rest/seller/get", headers: {}, body: nil)
      body = JSON.parse(File.read(File.join(dir, "seller_get.json")))["body"]["data"]

      assert_equal({ "seller_id" => "10", "status" => "ACTIVE" }, body.reject { |_, v| v == "[REDACTED]" })
      assert_equal 10, body.size
      refute_includes JSON.generate(body), "Changi"
    end
  end

  def test_error_responses_never_replace_a_fixture
    Dir.mktmpdir do |dir|
      refusal = { "code" => "IllegalAccessToken", "message" => "expired", "request_id" => "r" }
      limit = { "code" => "0", "success" => "false", "errorCodes" => ["ONLY_CB_SELLER_SUPPORTED"] }
      inner = FakeTransport.new(FakeTransport.json(refusal), FakeTransport.json(limit),
                                FakeTransport.json({ "code" => "0" }, status: 500))
      recorder = LiveHelper::Recorder.new(inner, secrets: [], label: "ph", dir:)
      3.times { recorder.call(method: :get, url: "https://h.test/rest/seller/get", headers: {}, body: nil) }

      assert_empty Dir.children(dir)
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
