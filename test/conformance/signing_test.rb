# frozen_string_literal: true

require_relative "helper"

module Conformance
  class SigningTest < Minitest::Test
    include Support

    def test_vectors
      refute_empty adapter.signing_vectors
      adapter.signing_vectors.each do |vector|
        assert_equal vector[:expected_base_string].b, vector[:base_string].b, "#{vector[:name]} base string"
        assert_equal vector[:expected_signature].downcase, vector[:signature].downcase, "#{vector[:name]} signature"
      end
    end

    def test_signature_timestamp_and_token_land_where_the_platform_expects
      adapter.signed_calls.each do |sample|
        client, transport = client_with(sample[:response])
        force(run_call(sample[:call], client, adapter.build_shop(client)))
        request = transport.requests.fetch(0)
        parts = adapter.signature_parts(request)

        assert_equal adapter.expected_signature(request), parts[:signature], sample[:name]
        assert_equal adapter.timestamp_for(adapter.fixed_time), parts[:timestamp], "#{sample[:name]} timestamp"
        assert_same_value sample[:token], parts[:access_token], "#{sample[:name]} token"
      end
    end

    def test_timestamp_comes_from_the_injected_clock
      later = adapter.fixed_time + 3600
      client, transport = client_with(adapter.read_success_response, clock: -> { later })
      adapter.read_call.call(client, adapter.build_shop(client))

      assert_equal adapter.timestamp_for(later), adapter.signature_parts(transport.requests[0])[:timestamp]
    end

    def test_body_sent_is_the_body_signed
      adapter.signed_calls.each do |sample|
        client, transport = client_with(sample[:response])
        force(run_call(sample[:call], client, adapter.build_shop(client)))
        request = transport.requests.fetch(0)
        signed = adapter.signed_body(request)

        assert_equal signed.b, request.body.to_s.b, sample[:name] unless signed.nil?

        assert(request.body.nil? || request.body.is_a?(String), "#{sample[:name]} body is a String or nil")
      end
    end
  end
end
