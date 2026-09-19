# frozen_string_literal: true

module LazadaRbApi
  # A token pair. Expiries are absolute UTC Times computed from the response and the injected clock.
  Grant = Data.define(:access_token, :refresh_token, :access_token_expires_at, :refresh_token_expires_at,
                      :shop_ids, :raw) do
    include Redaction

    def inspect
      "#<#{self.class.name} access_token=#{Redaction::REDACTED} refresh_token=#{Redaction::REDACTED} " \
        "access_token_expires_at=#{access_token_expires_at.inspect} " \
        "refresh_token_expires_at=#{refresh_token_expires_at.inspect} shop_ids=#{shop_ids.inspect}>"
    end
    alias_method :to_s, :inspect
  end

  # One shop authorized to the app. #locator is the Hash to pass to Client#shop ({} on Lazada).
  AuthorizedShop = Data.define(:shop_id, :name, :region, :authorization_expires_at, :locator, :raw)

  # A per-item failure inside a successful response. id and code are Strings.
  ItemError = Data.define(:id, :code, :message, :raw)

  # One page of a Pager. next_cursor is an opaque String, or nil on the last page.
  Page = Data.define(:items, :next_cursor, :total, :response)

  # A parsed inbound webhook (Lazada push).
  WebhookEvent = Data.define(:type, :code, :shop_id, :occurred_at, :data, :raw)
end
