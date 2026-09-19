# frozen_string_literal: true

# Conformance tests walk every adapter sample in one test, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "helper"

module Conformance
  class ResponseTest < Minitest::Test
    include Support

    def test_envelope_samples
      adapter.envelope_samples.each do |sample|
        client, = client_with(sample[:response])
        response = run_call(sample[:call], client, adapter.build_shop(client))
        expect = sample[:expect]

        assert_instance_of gem_module::Response, response, sample[:name]
        assert_equal expect[:data], response.data, sample[:name]
        assert_equal expect[:request_id], response.request_id, sample[:name]
        assert_equal expect[:warnings], response.warnings, sample[:name]
        assert_equal expect[:item_errors], response.item_errors.map { |e| [e.id, e.code, e.message] }, sample[:name]
        response.item_errors.each do |item_error|
          assert_instance_of gem_module::ItemError, item_error
          assert_kind_of String, item_error.id
          assert_kind_of String, item_error.code
        end
        assert_equal 200, response.http_status
        assert_kind_of String, response.endpoint
        assert response.endpoint.start_with?("/"), "#{sample[:name]} endpoint"
      end
    end

    def test_data_and_raw_are_deeply_frozen
      adapter.envelope_samples.each do |sample|
        client, = client_with(sample[:response])
        response = run_call(sample[:call], client, adapter.build_shop(client))

        assert_predicate response.data, :frozen?
        assert_predicate response.raw, :frozen?
        assert_predicate response, :frozen?
        assert_raises(FrozenError) { response.raw[response.raw.keys.first] = 1 }
      end
    end

    def test_platform_values_are_not_coerced
      sample = adapter.uncoerced_sample
      client, = client_with(sample[:response])
      response = run_call(sample[:call], client, adapter.build_shop(client))

      sample[:checks].each { |path, value| assert_equal value, response.data.dig(*path), path.join(".") }
    end

    def test_raw_is_the_body_exactly_as_received
      sample = adapter.envelope_samples.first
      client, = client_with(sample[:response])
      response = run_call(sample[:call], client, adapter.build_shop(client))

      assert_equal JSON.parse(sample[:response][:body]), response.raw
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
