# frozen_string_literal: true

module LazadaRbApi
  # Shared plumbing for the resource classes. Not part of the public contract.
  module Resources
    # Identity arguments accept a String or an Integer; Lazada's ids are integers.
    def self.integer_id(value, name)
      Integer(value.to_s, 10)
    rescue ArgumentError
      raise ArgumentError, "#{name} must be an integer id, got #{value.inspect}"
    end

    # Lazada's product payloads go in one parameter as {"Request":{"Product":{…}}}.
    def self.product_request(product)
      { "Request" => { "Product" => product } }
    end

    # The /product/price_quantity/update payload shared by stock and price updates: each native Sku entry gets
    # the ItemId.
    def self.price_quantity(item_id, skus)
      entries = skus.map { |sku| sku.to_h.transform_keys(&:to_s).merge("ItemId" => item_id.to_s) }
      { payload: product_request({ "Skus" => { "Sku" => entries } }) }
    end

    # One shop session's signed calls, handed to every resource so the resources never see the token directly.
    # public: true leaves the token off, for the endpoints Lazada documents as "No Authorization Required".
    class Session
      include Redaction

      attr_reader :connection

      def initialize(connection, access_token:)
        @connection = connection
        @access_token = access_token
        freeze
      end

      def get(path, query = {}, public: false)
        @connection.call(:get, path, query:, access_token: token(public))
      end

      def post(path, body, idempotent: false)
        @connection.call(:post, path, body:, access_token: @access_token, idempotent:)
      end

      def upload(path, fields, file)
        @connection.call(:post, path, body: fields, file:, access_token: @access_token)
      end

      def request(http_method, path, query:, body:, idempotent:)
        @connection.call(http_method, path, query:, body:, access_token: @access_token, idempotent:)
      end

      def inspect
        "#<#{self.class.name} access_token=#{Redaction::REDACTED}>"
      end

      private

      def token(public)
        public ? nil : @access_token
      end
    end

    class Base
      def initialize(session)
        @session = session
        freeze
      end

      def inspect
        "#<#{self.class.name}>"
      end

      private

      attr_reader :session

      def id!(value, name)
        Resources.integer_id(value, name)
      end

      def ids!(values, name, max)
        list = Array(values).map { |v| id!(v, name) }
        raise ArgumentError, "#{name} is empty" if list.empty?
        raise ArgumentError, "#{name} has #{list.size} ids; the maximum per call is #{max}" if list.size > max

        list
      end

      def page_size!(value, max)
        size = value.nil? ? max : Integer(value)
        raise ArgumentError, "page_size must be between 1 and #{max}, got #{size}" unless size.between?(1, max)

        size
      end

      def batch!(list, name, max)
        list = Array(list)
        raise ArgumentError, "#{name} is empty" if list.empty?
        raise ArgumentError, "#{name} has #{list.size} entries; the maximum per call is #{max}" if list.size > max

        list
      end

      def stringify(hash)
        (hash || {}).to_h.transform_keys(&:to_s)
      end

      def offset(cursor)
        Integer(cursor || 0)
      end

      # Offset paging that stops on a short or empty page, or once `total` items have been passed. `total` is
      # Lazada's own count, as sent (often a String); an unreadable total is ignored.
      def offset_page(response, items, offset, size, total = nil)
        items = Array(items).freeze
        after = offset + items.size
        known = Integer(total.to_s, 10, exception: false)
        more = items.size >= size && (known.nil? || after < known)
        Page.new(items:, next_cursor: more ? after.to_s : nil, total:, response:)
      end
    end
  end
  private_constant :Resources
end
