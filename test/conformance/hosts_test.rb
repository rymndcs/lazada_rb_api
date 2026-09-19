# frozen_string_literal: true

# Conformance tests walk every adapter sample in one test, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "helper"

module Conformance
  # Hosts are configuration, not code (CONTRACT.md "Hosts"): every named host is selectable, any URL can replace it,
  # and once custom hosts are configured no call reaches any other host.
  class HostsTest < Minitest::Test
    include Support

    CUSTOM = { base_url: "https://api.example.test", auth_base_url: "https://consent.example.test" }.freeze
    CUSTOM_TOKEN = { token_base_url: "https://token.example.test" }.freeze

    def custom_hosts
      token_host? ? CUSTOM.merge(CUSTOM_TOKEN) : CUSTOM
    end

    def read_url(**)
      client, transport = client_with(adapter.read_success_response, **)
      adapter.read_call.call(client, adapter.build_shop(client))
      [transport.requests.first.url, adapter.authorize(client)]
    end

    def token_url(**)
      sample = adapter.token_samples.first
      client, transport = client_with(sample[:response], **)
      sample[:call].call(client)
      transport.requests.first.url
    end

    def test_each_named_endpoint_selects_its_api_auth_and_token_host
      gem_module::ENDPOINTS.each do |name, hosts|
        api_url, auth_url = read_url(endpoint: name)
        token = token_url(endpoint: name)

        assert api_url.start_with?("#{hosts[:api]}/"), "#{name}: #{api_url}"
        assert auth_url.start_with?("#{hosts[:auth]}/"), "#{name}: #{auth_url}"
        assert token.start_with?("#{hosts[:token] || hosts[:api]}/"), "#{name} token: #{token}"
      end
    end

    def test_a_custom_url_replaces_each_host
      api_url, auth_url = read_url(base_url: "https://api.example.test/", auth_base_url: "https://consent.example.test")

      assert api_url.start_with?("https://api.example.test/"), "custom API host: #{api_url}"
      refute api_url.start_with?("https://api.example.test//"), api_url
      assert auth_url.start_with?("https://consent.example.test/"), "custom auth host: #{auth_url}"
    end

    def test_a_custom_url_replaces_the_token_host
      skip "this platform's token calls use the API host" unless token_host?
      token = token_url(token_base_url: "https://token.example.test/")

      assert token.start_with?("https://token.example.test/"), "custom token host: #{token}"
      refute token.start_with?("https://token.example.test//"), token
    end

    def test_the_default_endpoint_is_a_named_endpoint
      client, = client_with

      assert_includes gem_module::ENDPOINTS.keys, client.endpoint
    end

    def test_unknown_endpoint_and_malformed_urls_are_configuration_errors
      assert_raises(gem_module::ConfigurationError) { client_with(endpoint: :nowhere) }
      assert_raises(gem_module::ConfigurationError) { client_with(base_url: "not a url") }
      assert_raises(gem_module::ConfigurationError) { client_with(auth_base_url: "ftp://example.test") }
      assert_raises(gem_module::ConfigurationError) { client_with(token_base_url: "not a url") } if token_host?
    end

    def test_custom_hosts_are_the_only_hosts_any_call_reaches
      adapter.shared_calls.each do |sample|
        client, transport = client_with(sample[:response], **custom_hosts)
        force(run_call(sample[:call], client, adapter.build_shop(client)))
        token_call = token_host? && CONTRACT[:token_calls].include?(sample[:name])
        expected = token_call ? "token.example.test" : "api.example.test"

        transport.requests.each { |request| assert_equal expected, request.uri.host, sample[:name] }
      end
      client, = client_with(**custom_hosts)

      assert_equal "consent.example.test", URI(adapter.authorize(client)).host
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
