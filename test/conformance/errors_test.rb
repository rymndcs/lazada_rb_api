# frozen_string_literal: true

# Conformance tests walk every adapter sample in one test, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "helper"

module Conformance
  class ErrorsTest < Minitest::Test
    include Support

    def raise_from(response, call: adapter.read_call)
      client, transport = client_with(response)
      error = assert_raises(gem_module::Error) { force(run_call(call, client, adapter.build_shop(client))) }
      [error, transport]
    end

    def test_every_api_error_class_has_a_documented_sample_or_is_declared_absent
      api_classes = CONTRACT[:errors].select { |_, parent| parent == "ApiError" }.keys
      covered = adapter.error_samples.map { |s| s[:class_name] } + adapter.error_classes_without_platform_code

      assert_empty api_classes - covered
    end

    def test_documented_samples_raise_their_class
      adapter.error_samples.each do |sample|
        error, = raise_from(sample[:response])

        assert_instance_of const(sample[:class_name]), error, sample[:code]
        assert_kind_of String, error.code
        assert_equal sample[:code], error.code
        assert_equal sample[:request_id], error.request_id
        assert_equal sample[:retryable], error.retryable?, "#{sample[:class_name]} #{sample[:code]} retryable?"
        assert_kind_of Integer, error.http_status
        assert_kind_of String, error.endpoint
        assert_kind_of Array, error.detail
        if sample[:retry_after] == :positive
          assert_operator error.retry_after, :>, 0
        else
          assert_nil error.retry_after
        end
      end
    end

    def test_an_unmapped_code_raises_plain_api_error
      error, = raise_from(adapter.unmapped_error_response)

      assert_instance_of gem_module::ApiError, error
      refute_predicate error, :retryable?
    end

    def test_server_error_on_a_non_idempotent_write_is_not_retryable
      adapter.write_calls.reject { |w| CONTRACT[:write_idempotency].fetch(w[:name]) }.each do |write|
        error, = raise_from(adapter.server_error_response, call: write[:call])

        assert_instance_of gem_module::ServerError, error
        refute_predicate error, :retryable?, write[:name]
      end
    end

    def test_server_error_on_an_idempotent_call_is_retryable
      idempotent_writes = adapter.write_calls.select { |w| CONTRACT[:write_idempotency][w[:name]] }
      calls = [adapter.read_call] + idempotent_writes.map { |w| w[:call] }
      calls.each do |call|
        error, = raise_from(adapter.server_error_response, call:)

        assert_predicate error, :retryable?
      end
    end

    def test_transport_error_retryable_only_when_idempotent
      read_error, = raise_from(gem_module::TransportError.new("read timeout"))

      assert_instance_of gem_module::TransportError, read_error
      assert_predicate read_error, :retryable?
      adapter.write_calls.reject { |w| CONTRACT[:write_idempotency].fetch(w[:name]) }.each do |write|
        error, = raise_from(gem_module::TransportError.new("read timeout"), call: write[:call])

        refute_predicate error, :retryable?, write[:name]
      end
    end

    def test_network_exceptions_from_a_custom_transport_become_transport_errors
      error, = raise_from(Errno::ECONNRESET.new)

      assert_instance_of gem_module::TransportError, error
    end

    def test_http_5xx_without_a_platform_body_is_a_server_error
      error, = raise_from(FakeTransport.json("<html>bad gateway</html>", status: 502))

      assert_instance_of gem_module::ServerError, error
      assert_equal "502", error.code
    end

    def test_http_429_with_retry_after_header
      error, = raise_from(FakeTransport.json("", status: 429, headers: { "Retry-After" => "7" }))

      assert_instance_of gem_module::RateLimitError, error
      assert_in_delta 7.0, error.retry_after
      assert_predicate error, :retryable?
    end

    def test_error_carries_the_parsed_response_when_the_body_parsed
      error, = raise_from(adapter.unmapped_error_response)

      assert_instance_of gem_module::Response, error.response
      assert_predicate error.response.raw, :frozen?
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
