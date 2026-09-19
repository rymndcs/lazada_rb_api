# frozen_string_literal: true

# Shared verbatim by the three sibling gems. Loads the gem's own test/test_helper.rb and test/conformance_adapter.rb
# (the only per-gem part of the suite) and the contract.
#
# ConformanceAdapter must respond to (every "response" is a FakeTransport response Hash):
#   gem_module, gem_name, fixed_time
#   build_client(transport:, clock: nil, logger: nil, retry_policy: nil, **client_options) -> Client
#   build_shop(client) -> Shop                     locator -> the Hash build_shop passes to client.shop
#   secrets -> Array<String> that must never appear in logs, exception messages or inspect output
#   authorize(client) -> String                    the consent URL, built the platform's way
#   read_call -> ->(client, shop) { ... }          read_success_response
#   shared_calls -> [{ name:, call: ->(client, shop), response: }]   one entry per CONTRACT[:shared_calls] name
#   write_calls -> [{ name:, call: ->(shop), response: }]            one per CONTRACT[:write_idempotency] name
#   batch_calls -> [{ name:, call: ->(shop, ids) }]                  one per CONTRACT[:batch_constants] name
#   server_error_response, rate_limit_response, unmapped_error_response
#   error_samples -> [{ class_name:, response:, code:, request_id:, retryable:, retry_after: nil|:positive }]
#   error_classes_without_platform_code -> class names the platform documents no code for
#   envelope_samples -> [{ name:, call: ->(client, shop), response:,
#                          expect: { data:, request_id:, warnings:, item_errors: [[id, code, message]] } }]
#   uncoerced_sample -> { call:, response:, checks: [[path, value]] } platform values that must come back untouched
#   pagers -> [{ name:, call: ->(client, shop, **opts) -> Pager, pages: [r1, r2, r3], final_variants: [r, r],
#                page_size_key:, max_page_size: Integer|nil, cap: nil | { responses: [...] }, resumable: false? }]
#   request_identity(request) -> what makes a request the same request, minus signature and timestamp
#   signing_vectors -> [{ name:, base_string:, expected_base_string:, signature:, expected_signature: }]
#   signed_calls -> [{ name:, call: ->(client, shop), response:, token: String|nil }]
#   signature_parts(request) -> { signature:, timestamp:, access_token: } read from where the platform puts them
#   expected_signature(request) -> the signature recomputed independently from the request as sent
#   timestamp_for(time) -> the platform's timestamp for a Time
#   signed_body(request) -> the body bytes the signature covers, or nil when the platform does not sign the body
#   webhook_credentials -> { app_key:, app_secret: }, webhook_url_required? -> true|false
#   webhook_vectors -> [{ name:, raw_body:, signature:, url: }]
#   webhook_parse_samples -> [{ raw_body:, expect: { type:, code:, shop_id:, occurred_at: } }]
#   token_samples -> [{ name:, call: ->(client), response:, expect: { access_token:, refresh_token:,
#                       access_expires_in:, refresh_expires_in:, shop_ids: } }]
#   extension_files -> gem-specific files the layout must contain
require "test_helper"
require "conformance_adapter"
require_relative "contract"

module Conformance
  class CapturingLogger
    attr_reader :lines

    def initialize
      @lines = []
    end

    %i[debug info warn error fatal unknown].each do |level|
      define_method(level) do |message = nil, &block|
        @lines << (message || block&.call).to_s
        true
      end
    end
  end

  module Support
    def adapter
      ConformanceAdapter
    end

    def gem_module
      adapter.gem_module
    end

    def const(name)
      name.split("::").reduce(gem_module) { |mod, part| mod.const_get(part) }
    end

    def client_with(*responses, **)
      transport = FakeTransport.new(*responses)
      [adapter.build_client(transport:, **), transport]
    end

    def shop_with(*responses, **)
      client, transport = client_with(*responses, **)
      [adapter.build_shop(client), transport]
    end

    def run_call(call, client, shop)
      call.arity == 1 ? call.call(shop) : call.call(client, shop)
    end

    # assert_equal, or assert_nil when nil is expected (Minitest 6 refuses assert_equal nil).
    def assert_same_value(expected, actual, message)
      expected.nil? ? assert_nil(actual, message) : assert_equal(expected, actual, message)
    end

    # True when the gem's ENDPOINTS carry a separate :token host, overridable with the declared token_base_url:.
    def token_host?
      gem_module::EXTENSIONS.key?("Client#token_base_url")
    end

    # Pager results are lazy: force one page so the call makes its request.
    def force(result)
      result.is_a?(gem_module::Pager) ? result.first_page : result
    end
  end
end
