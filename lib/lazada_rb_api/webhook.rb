# frozen_string_literal: true

module LazadaRbApi
  # Lazada push (webhook) verification and parsing: pure functions, no HTTP.
  # https://open.lazada.com/apps/doc/doc?nodeId=29524&docId=120168
  #
  # The Authorization header is HEX(HMAC-SHA256(app_secret, app_key + raw_body)). Hash the raw body as received,
  # never re-serialized JSON. The receiver must answer HTTP 200 within 500 ms, or Lazada retries every 30 minutes, up
  # to 12 times. The callback URL must serve a CA-issued OV or EV certificate; DV and self-signed ones are refused.
  module Webhook
    # message_type => type. 8: authorization token expiration alert (48 hours ahead, then daily); 1: product
    # quality control status. Every other type (0 trade order, 3/4/5 product, 12 category tree, 13 seller status,
    # ...) is :other with its code kept.
    TYPES = { "8" => :authorization_expiring, "1" => :product_status }.freeze
    # Lazada sends epoch seconds in most pushes and epoch milliseconds in the trade order push.
    MILLISECONDS = 100_000_000_000

    module_function

    # => true | false. url: is accepted for the shared interface; Lazada's base string does not use it.
    def verify(raw_body:, signature:, app_key:, app_secret:, url: nil)
      _ = url
      return false unless signature.is_a?(String) && raw_body.is_a?(String)

      expected = Signer.push_sign(app_secret, Signer.push_base_string(app_key, raw_body))
      given = signature.downcase
      given.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(expected, given)
    end

    # => WebhookEvent. Raises ArgumentError when the body is not a JSON object.
    def parse(raw_body)
      raw = JSON.parse(raw_body.to_s)
      raise ArgumentError, "webhook body is not a JSON object" unless raw.is_a?(Hash)

      event(Envelope.deep_freeze(raw))
    rescue JSON::ParserError
      raise ArgumentError, "webhook body is not valid JSON"
    end

    def event(raw)
      code = raw["message_type"].to_s
      data = raw["data"].is_a?(Hash) ? raw["data"] : {}.freeze
      WebhookEvent.new(type: TYPES.fetch(code, :other), code:, shop_id: seller_id(raw, data),
                       occurred_at: time(raw["timestamp"]), data:, raw:)
    end
    private_class_method :event

    # The token expiration alert sends "seller_id": "null" at the top level and the real one inside data.
    def seller_id(raw, data)
      [raw["seller_id"], data["seller_id"]].map(&:to_s).find { |id| !id.empty? && id != "null" }
    end
    private_class_method :seller_id

    def time(value)
      return nil unless value.is_a?(Integer)

      value >= MILLISECONDS ? Time.at(Rational(value, 1000)).utc : Time.at(value).utc
    end
    private_class_method :time
  end
end
