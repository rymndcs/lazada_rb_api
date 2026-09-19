# frozen_string_literal: true

require "test_helper"
require "date"
require "fileutils"
require "logger"

# Opt-in live tests: `rake test:live`. They never run under plain `rake`, and they skip unless credentials are set.
# Lazada has no sandbox host: every live test runs against a real, authorized store.
#
#   LAZADA_APP_KEY, LAZADA_APP_SECRET, LAZADA_ACCESS_TOKEN   required
#   LAZADA_ENDPOINT      a name from LazadaRbApi::ENDPOINTS (default ph); it must be the token's country
#   LAZADA_BASE_URL      optional API host override
#   LAZADA_RECORD=1      writes every successful response (2xx, code "0", success not false), redacted, over
#                        test/fixtures/<path>.json with "_source" naming the recording, replacing the documentation
#                        sample. Error responses are never recorded, and neither is any order response
#                        (/orders/get, /order/get, /order/items/get): orders stay on documentation samples.
#                        Customer personal data (email, phone, name, nickname, address, and whole recipient or
#                        buyer objects) is redacted wherever it appears (captain decision 2026-09-20).
#
# The live tests only READ. They never refresh a token (the refresh token may be single use) and never write.
module LiveHelper
  REQUIRED = %w[LAZADA_APP_KEY LAZADA_APP_SECRET LAZADA_ACCESS_TOKEN].freeze
  SECRET_KEYS = /token|secret|\Asign\z|\Acode\z|email|account/i
  # Order endpoints are never recorded: their responses carry real customers' names, phones and addresses.
  ORDER_PATHS = %r{\A/orders?/}
  # Customer personal-data words, matched case-insensitively against each word of a key (snake_case or camelCase,
  # digits ignored: address1, phone2, customer_first_name, nickName). A matching key loses its whole value.
  PERSONAL_WORDS = %w[email phone name nickname address].freeze
  # A Hash or Array under a key naming a recipient or buyer (recipient_info, buyer_address) is redacted whole.
  PERSON_OBJECTS = /recipient|buyer/i

  module_function

  def configured?
    REQUIRED.all? { |key| !ENV.fetch(key, "").empty? }
  end

  def credentials
    REQUIRED.map { |key| ENV.fetch(key, nil) }
  end

  def endpoint
    ENV.fetch("LAZADA_ENDPOINT", "ph").to_sym
  end

  def client
    options = { endpoint: }
    options[:base_url] = ENV["LAZADA_BASE_URL"] if ENV["LAZADA_BASE_URL"]
    logger = Logger.new($stderr, level: ENV["LAZADA_LIVE_DEBUG"] ? Logger::DEBUG : Logger::INFO)
    LazadaRbApi::Client.new(app_key: ENV.fetch("LAZADA_APP_KEY"), app_secret: ENV.fetch("LAZADA_APP_SECRET"),
                            transport:, logger:, **options)
  end

  def shop
    client.shop(access_token: ENV.fetch("LAZADA_ACCESS_TOKEN"))
  end

  def transport
    net = LazadaRbApi::Transport::NetHttp.new
    ENV["LAZADA_RECORD"] == "1" ? Recorder.new(net, secrets: credentials, label: endpoint.to_s) : net
  end

  # Wraps a transport and records each successful response as a redacted fixture.
  class Recorder
    def initialize(inner, secrets:, label:, dir: Fixtures::DIR)
      @inner = inner
      @dir = dir
      @secrets = secrets.compact.reject(&:empty?)
      @label = label.strip
    end

    def call(method:, url:, headers:, body:)
      result = @inner.call(method:, url:, headers:, body:)
      record(URI(url).path, result)
      result
    end

    private

    def record(path, result)
      api_path = path.delete_prefix("/rest")
      return if api_path.match?(ORDER_PATHS)

      parsed = JSON.parse(result[:body])
      return unless recordable?(result[:status], parsed)

      fixture = { "_source" => { "url" => "https://open.lazada.com/apps/doc/api?path=#{api_path}",
                                 "pulled" => Date.today.iso8601,
                                 "origin" => "recorded live #{Date.today.iso8601} (#{@label}), redacted" },
                  "status" => result[:status], "headers" => {}, "body" => redact(parsed) }
      File.write(File.join(@dir, "#{api_path.delete_prefix("/").tr("/", "_")}.json"),
                 "#{JSON.pretty_generate(fixture)}\n")
    rescue JSON::ParserError
      nil
    end

    def recordable?(status, parsed)
      (200..299).cover?(status.to_i) && parsed.is_a?(Hash) && parsed["code"].to_s == "0" &&
        ![false, "false"].include?(parsed["success"])
    end

    def redact(value)
      case value
      when Hash then value.to_h { |k, v| [k, redact_member(k, v)] }
      when Array then value.map { |v| redact(v) }
      when String then @secrets.reduce(value) { |text, secret| text.gsub(secret, "[REDACTED]") }
      else value
      end
    end

    def redact_member(key, value)
      return "[REDACTED]" if personal?(key, value)

      key.to_s.match?(SECRET_KEYS) && value.is_a?(String) ? "[REDACTED]" : redact(value)
    end

    def personal?(key, value)
      words = key.to_s.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.delete("0-9").split(/[^a-z]+/)
      return true if words.intersect?(PERSONAL_WORDS)

      (value.is_a?(Hash) || value.is_a?(Array)) && key.to_s.match?(PERSON_OBJECTS)
    end
  end

  # Include in a live test class: every test skips unless the credentials are set.
  module Gate
    def setup
      super
      return if LiveHelper.configured?

      skip "set LAZADA_APP_KEY, LAZADA_APP_SECRET and LAZADA_ACCESS_TOKEN to run live tests " \
           "(see test/live/live_helper.rb)"
    end
  end
end
