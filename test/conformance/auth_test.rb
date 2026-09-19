# frozen_string_literal: true

# Conformance tests walk every adapter sample in one test, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "helper"

module Conformance
  class AuthTest < Minitest::Test
    include Support

    def test_token_responses_become_grants_with_absolute_expiries_from_the_injected_clock
      refute_empty adapter.token_samples
      adapter.token_samples.each do |sample|
        client, transport = client_with(sample[:response])
        grant = sample[:call].call(client)
        expect = sample[:expect]

        assert_instance_of gem_module::Grant, grant
        assert_equal 1, transport.requests.size
        assert_equal expect[:access_token], grant.access_token
        assert_equal expect[:refresh_token], grant.refresh_token
        assert_equal adapter.fixed_time + expect[:access_expires_in], grant.access_token_expires_at, sample[:name]
        assert_predicate grant.access_token_expires_at, :utc?
        if expect[:refresh_expires_in]
          assert_equal adapter.fixed_time + expect[:refresh_expires_in], grant.refresh_token_expires_at
        else
          assert_nil grant.refresh_token_expires_at
        end

        assert_equal expect[:shop_ids], grant.shop_ids
        grant.shop_ids.each { |id| assert_kind_of String, id }
        assert_predicate grant.raw, :frozen?
      end
    end

    def test_refresh_is_never_called_implicitly
      error = adapter.error_samples.find { |s| s[:class_name] == "AuthenticationError" }
      client, transport = client_with(error[:response])

      assert_raises(gem_module::AuthenticationError) { adapter.read_call.call(client, adapter.build_shop(client)) }
      assert_equal 1, transport.requests.size
    end

    def test_shop_rejects_a_missing_or_unknown_locator_key
      client, = client_with
      keys = gem_module::Shop::LOCATOR_KEYS

      assert_raises(ArgumentError) { client.shop(access_token: "t", **adapter.locator, not_a_locator_key: 1) }
      assert_raises(ArgumentError) { client.shop(access_token: "t") } unless keys.empty?
      shop = adapter.build_shop(client)

      assert_predicate shop.locator, :frozen?
      assert_equal keys.sort, shop.locator.keys.sort
      assert_predicate shop, :frozen?
    end

    def test_authorized_shops_are_authorized_shop_values_with_a_usable_locator
      sample = adapter.shared_calls.find { |c| c[:name] == "client.authorized_shops" }
      client, = client_with(sample[:response])
      shops = run_call(sample[:call], client, nil).first_page.items

      refute_empty shops
      shops.each do |ref|
        assert_instance_of gem_module::AuthorizedShop, ref
        assert_kind_of String, ref.shop_id
        assert_equal gem_module::Shop::LOCATOR_KEYS.sort, ref.locator.keys.sort
        assert_equal ref.region.upcase, ref.region if ref.region

        assert_instance_of gem_module::Shop, client.shop(access_token: "token", **ref.locator)
      end
    end

    def test_client_is_immutable
      client, = client_with

      assert_predicate client, :frozen?
      assert_kind_of String, client.app_key
      assert_includes gem_module::ENDPOINTS.keys, client.endpoint
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
