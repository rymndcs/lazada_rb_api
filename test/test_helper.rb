# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "stringio"
require "lazada_rb_api"
require_relative "support/fake_transport"

# Loads test/fixtures/<name>.json. Every fixture names its source in "_source": the doc URL and pull date, or
# "recorded live <date>".
module Fixtures
  DIR = File.expand_path("fixtures", __dir__)

  module_function

  def load(name)
    JSON.parse(File.read(File.join(DIR, "#{name}.json")))
  end

  # => a FakeTransport response Hash. Overrides are merged into the body.
  def response(name, status: nil, **overrides)
    doc = load(name)
    body = doc.fetch("body").merge(overrides.transform_keys(&:to_s))
    FakeTransport.json(body, status: status || doc.fetch("status"), headers: doc.fetch("headers", {}))
  end

  def body(name)
    load(name).fetch("body")
  end
end
