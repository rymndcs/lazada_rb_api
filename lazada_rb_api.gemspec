# frozen_string_literal: true

require_relative "lib/lazada_rb_api/version"

Gem::Specification.new do |spec|
  spec.name = "lazada_rb_api"
  spec.version = LazadaRbApi::VERSION
  spec.authors = ["Raymond Chua Sing"]
  spec.email = ["rcs@pragdev.io"]
  spec.summary = "Ruby client for the Lazada Open Platform API"
  spec.description = "Signed HTTP client for the Lazada Open Platform API: authorization, catalogue, product, " \
                     "stock, price and order reads, and push verification. No runtime dependencies."
  spec.homepage = "https://github.com/rymndcs/lazada_rb_api"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "CONTRACT.md", "LICENSE"]
  spec.require_paths = ["lib"]
end
