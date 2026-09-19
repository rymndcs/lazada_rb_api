# frozen_string_literal: true

# Conformance tests walk every adapter sample in one test, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "helper"

module Conformance
  class WebhookTest < Minitest::Test
    include Support

    def verify(vector, **overrides)
      gem_module::Webhook.verify(raw_body: vector[:raw_body], signature: vector[:signature], url: vector[:url],
                                 **adapter.webhook_credentials, **overrides)
    end

    def test_vectors_verify
      refute_empty adapter.webhook_vectors
      adapter.webhook_vectors.each { |vector| assert verify(vector), "#{vector[:name]} verifies" }
    end

    def test_upper_case_hex_verifies
      adapter.webhook_vectors.each { |vector| assert verify(vector, signature: vector[:signature].upcase) }
    end

    def test_tampered_missing_wrong_length_and_bearer_signatures_fail
      adapter.webhook_vectors.each do |vector|
        refute verify(vector, raw_body: "#{vector[:raw_body]} "), "tampered body"
        refute verify(vector, signature: nil), "missing header"
        refute verify(vector, signature: ""), "empty header"
        refute verify(vector, signature: vector[:signature][0..-3]), "wrong length"
        refute verify(vector, signature: "Bearer #{vector[:signature]}"), "Bearer prefix"
        refute verify(vector, app_secret: "#{adapter.webhook_credentials[:app_secret]}x"), "wrong secret"
      end
    end

    def test_url_requirement
      vector = adapter.webhook_vectors.first
      if adapter.webhook_url_required?
        assert_raises(ArgumentError) { verify(vector, url: nil) }
        refute verify(vector, url: "#{vector[:url]}/other")
      else
        assert verify(vector, url: nil)
      end
    end

    def test_client_verify_webhook_raises_on_a_bad_signature_and_parses_a_good_one
      client, = client_with
      vector = adapter.webhook_vectors.first
      event = client.verify_webhook(raw_body: vector[:raw_body], signature: vector[:signature], url: vector[:url])

      assert_instance_of gem_module::WebhookEvent, event
      assert_raises(gem_module::WebhookSignatureError) do
        client.verify_webhook(raw_body: vector[:raw_body], signature: "0" * 64, url: vector[:url])
      end
    end

    def test_parse_normalizes_type_code_shop_id_and_occurred_at
      refute_empty adapter.webhook_parse_samples
      adapter.webhook_parse_samples.each do |sample|
        event = gem_module::Webhook.parse(sample[:raw_body])

        sample[:expect].each { |field, value| assert_same_value value, event.public_send(field), field.to_s }
        assert_includes CONTRACT[:webhook_types], event.type
        assert_kind_of String, event.code
        assert_predicate event.data, :frozen?
        assert_predicate event.raw, :frozen?
        assert_equal JSON.parse(sample[:raw_body]), event.raw
      end
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
