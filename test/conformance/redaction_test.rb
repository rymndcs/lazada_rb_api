# frozen_string_literal: true

# Conformance tests walk every adapter sample in one test, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "helper"
require "pp"

module Conformance
  class RedactionTest < Minitest::Test
    include Support

    def assert_clean(text, context)
      adapter.secrets.each { |secret| refute_includes text.to_s, secret, "#{context} leaks a secret" }
    end

    def test_logs_carry_no_secret_token_code_or_signature
      logger = CapturingLogger.new
      signatures = []
      adapter.shared_calls.each do |sample|
        client, transport = client_with(sample[:response], logger:)
        force(run_call(sample[:call], client, adapter.build_shop(client)))
        signatures << adapter.signature_parts(transport.requests[0])[:signature]
      end

      refute_empty logger.lines
      logger.lines.each do |line|
        assert_clean(line, "log line")
        signatures.compact.each { |sig| refute_includes line, sig, "log line leaks a signature" }
      end
    end

    def test_inspect_and_pretty_print_redact
      client, = client_with(*adapter.token_samples.map { |s| s[:response] })
      shop = adapter.build_shop(client)
      grants = adapter.token_samples.map { |s| s[:call].call(client) }

      [client, shop, client.auth, *grants].each do |object|
        assert_clean(object.inspect, "#{object.class} inspect")
        assert_clean(object.to_s, "#{object.class} to_s")
        assert_clean(object.pretty_inspect, "#{object.class} pretty_inspect")
      end
      assert_includes client.inspect, "[REDACTED]"
    end

    def test_exception_messages_carry_no_secrets
      samples = adapter.error_samples.map { |s| s[:response] } + [adapter.unmapped_error_response]
      samples.each do |response|
        client, = client_with(response)
        error = assert_raises(gem_module::Error) { adapter.read_call.call(client, adapter.build_shop(client)) }

        assert_clean(error.message, "exception message")
        assert_clean(error.inspect, "exception inspect")
        assert_clean(error.full_message(highlight: false), "exception full message")
      end
    end

    def test_configuration_errors_do_not_echo_the_secret
      error = assert_raises(gem_module::ConfigurationError) do
        adapter.build_client(transport: FakeTransport.new, endpoint: :no_such_endpoint)
      end
      assert_clean(error.message, "configuration error")
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
