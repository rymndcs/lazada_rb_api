# frozen_string_literal: true

# Conformance tests walk every adapter sample in one test, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "helper"

module Conformance
  class PackagingTest < Minitest::Test
    include Support

    ROOT = File.expand_path("../..", __dir__)

    def spec
      @spec ||= Dir.chdir(ROOT) { Gem::Specification.load("#{adapter.gem_name}.gemspec") }
    end

    def test_zero_runtime_dependencies_and_the_ruby_floor
      assert_empty spec.runtime_dependencies
      assert_equal Gem::Requirement.new(">= 3.3"), spec.required_ruby_version
      assert_equal adapter.gem_name, spec.name
      assert_equal gem_module::VERSION, spec.version.to_s
      assert_equal "MIT", spec.license
    end

    def test_the_shared_file_layout_exists
      gem = adapter.gem_name
      files = %W[
        .rubocop.yml CHANGELOG.md CONTRACT.md Gemfile Gemfile.lock Rakefile LICENSE README.md #{gem}.gemspec
        lib/#{gem}.rb lib/#{gem}/version.rb lib/#{gem}/client.rb lib/#{gem}/shop.rb lib/#{gem}/auth.rb
        lib/#{gem}/endpoints.rb lib/#{gem}/connection.rb lib/#{gem}/signer.rb lib/#{gem}/response.rb
        lib/#{gem}/pager.rb lib/#{gem}/values.rb lib/#{gem}/errors.rb lib/#{gem}/error_table.rb
        lib/#{gem}/retry_policy.rb lib/#{gem}/webhook.rb lib/#{gem}/multipart.rb lib/#{gem}/transport/net_http.rb
        lib/#{gem}/resources/categories.rb lib/#{gem}/resources/brands.rb lib/#{gem}/resources/media.rb
        lib/#{gem}/resources/products.rb lib/#{gem}/resources/stock.rb lib/#{gem}/resources/prices.rb
        lib/#{gem}/resources/orders.rb
        test/test_helper.rb test/support/fake_transport.rb test/conformance_adapter.rb test/conformance/MANIFEST
      ] + adapter.extension_files
      missing = files.reject { |file| File.file?(File.join(ROOT, file)) }

      assert_empty missing
      assert File.directory?(File.join(ROOT, "test/live")), "test/live exists"
    end

    def test_packaged_files_include_the_contract
      assert_includes spec.files, "CONTRACT.md"
      assert_includes spec.files, "lib/#{adapter.gem_name}.rb"
    end

    def test_the_contract_document_states_the_contract_version
      assert_includes File.read(File.join(ROOT, "CONTRACT.md")), "CONTRACT_VERSION = \"#{CONTRACT[:version]}\""
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
