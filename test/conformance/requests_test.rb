# frozen_string_literal: true

# Conformance tests walk every adapter sample in one test, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "helper"

module Conformance
  class RequestsTest < Minitest::Test
    include Support

    def test_the_adapter_covers_every_shared_call
      assert_empty CONTRACT[:shared_calls] - adapter.shared_calls.map { |c| c[:name] }
      assert_empty CONTRACT[:write_idempotency].keys - adapter.write_calls.map { |c| c[:name] }
      assert_empty CONTRACT[:batch_constants].keys - adapter.batch_calls.map { |c| c[:name] }
    end

    def test_one_method_call_makes_exactly_one_request
      adapter.shared_calls.each do |sample|
        client, transport = client_with(sample[:response])
        force(run_call(sample[:call], client, adapter.build_shop(client)))

        assert_equal 1, transport.requests.size, sample[:name]
      end
    end

    def test_writes_are_not_retried_by_default
      adapter.write_calls.each do |write|
        shop, transport = shop_with(adapter.server_error_response, write[:response])

        assert_raises(gem_module::ServerError) { write[:call].call(shop) }
        assert_equal 1, transport.requests.size, write[:name]
      end
    end

    def policy(sleeps)
      gem_module::RetryPolicy.new(max_retries: 2, base: 0.0, jitter: 0.0, sleeper: ->(s) { sleeps << s })
    end

    def test_opt_in_policy_retries_only_retryable_errors
      adapter.write_calls.each do |write|
        sleeps = []
        shop, transport = shop_with(adapter.server_error_response, write[:response], retry_policy: policy(sleeps))
        idempotent = CONTRACT[:write_idempotency].fetch(write[:name])

        if idempotent
          assert_instance_of gem_module::Response, write[:call].call(shop)
          assert_equal 2, transport.requests.size, write[:name]
        else
          assert_raises(gem_module::ServerError) { write[:call].call(shop) }
          assert_equal 1, transport.requests.size, write[:name]
        end
      end
    end

    def test_rate_limited_calls_are_retried_under_an_opt_in_policy_and_each_retry_re_signs
      sleeps = []
      times = [adapter.fixed_time, adapter.fixed_time + 2]
      client, transport = client_with(adapter.rate_limit_response, adapter.read_success_response,
                                      retry_policy: policy(sleeps), clock: -> { times.shift || adapter.fixed_time })
      adapter.read_call.call(client, adapter.build_shop(client))

      assert_equal 2, transport.requests.size
      assert_equal 1, sleeps.size
      first, second = transport.requests.map { |r| adapter.signature_parts(r) }

      refute_equal first[:timestamp], second[:timestamp]
      refute_equal first[:signature], second[:signature]
      assert_equal adapter.expected_signature(transport.requests[1]), second[:signature]
    end

    def test_retries_stop_at_max_retries
      sleeps = []
      responses = Array.new(3) { adapter.rate_limit_response }
      client, transport = client_with(*responses, retry_policy: policy(sleeps))

      assert_raises(gem_module::RateLimitError) { adapter.read_call.call(client, adapter.build_shop(client)) }
      assert_equal 3, transport.requests.size
      assert_equal 2, sleeps.size
    end

    def test_retry_delay_formula
      policy = gem_module::RetryPolicy.new(max_retries: 5, base: 1.0, cap: 60.0, jitter: 0.0, sleeper: ->(_) {})
      error = gem_module::RateLimitError.new("slow down", code: "x", retry_after: 10.0)

      assert_in_delta 1.0, policy.delay_for(gem_module::RateLimitError.new("x"), 0)
      assert_in_delta 8.0, policy.delay_for(gem_module::RateLimitError.new("x"), 3)
      assert_in_delta 60.0, policy.delay_for(gem_module::RateLimitError.new("x"), 10)
      assert_in_delta 10.0, policy.delay_for(error, 0)
      assert_equal 0, gem_module::RetryPolicy.none.max_retries
    end

    def test_batch_maximum_raises_argument_error_without_a_request
      adapter.batch_calls.each do |batch|
        max = gem_module::Products.const_get(CONTRACT[:batch_constants].fetch(batch[:name]))
        shop, transport = shop_with

        assert_raises(ArgumentError, batch[:name]) { batch[:call].call(shop, (1..(max + 1)).to_a) }
        assert_raises(ArgumentError, batch[:name]) { batch[:call].call(shop, []) }
        assert_empty transport.requests
      end
    end

    def test_request_escape_hatch_validates_the_method
      client, transport = client_with

      assert_raises(ArgumentError) { client.request(:patch, "/x") }
      assert_empty transport.requests
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
