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
