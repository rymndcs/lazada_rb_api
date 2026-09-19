# frozen_string_literal: true

module LazadaRbApi
  # One shop session: the app client plus this store's access token. Immutable. Lazada's locator is empty: one token
  # is one store, and the host carries the country.
  class Shop
    include Redaction

    LOCATOR_KEYS = [].freeze

    attr_reader :locator, :categories, :brands, :media, :products, :stock, :prices, :orders

    def initialize(connection, access_token:)
      raise ArgumentError, "access_token: is empty" if access_token.to_s.empty?

      @session = Resources::Session.new(connection, access_token: access_token.to_s)
      @locator = {}.freeze
      build_resources
      freeze
    end

    # GET /seller/get: seller_id, name, short_code, status (ACTIVE / INACTIVE / DELETED), verified, cb.
    # https://open.lazada.com/apps/doc/api?path=/seller/get
    def info
      @session.get(Endpoints::SELLER)
    end

    # GET /product/seller/item/getPreQcRules (GetPreQcRules). The payload is under `values`: item_limit,
    # item_count and restricted_cate_ids. Lazada requires option and option_set ([1] item limit, [2] restricted
    # category ids, [1, 2] both): pass them in params. Lazada also offers GetSellerItemLimit (see #item_limit),
    # documented for cross-border sellers only; which one to rely on is the caller's choice.
    # https://open.lazada.com/apps/doc/api?path=/product/seller/item/getPreQcRules
    def limits(**params)
      @session.get(Endpoints::PRE_QC_RULES, params)
    end

    # Extension. GET /product/seller/item/limit (GetSellerItemLimit): itemLimit, onlineItemCount, payItemCnt and
    # payByrCnt. Documented "only cb seller supported" (ONLY_CB_SELLER_SUPPORTED for local sellers, a
    # PermissionError); 10 QPS per seller.
    # https://open.lazada.com/apps/doc/api?path=/product/seller/item/limit
    def item_limit
      @session.get(Endpoints::SELLER_ITEM_LIMIT)
    end

    # The escape hatch: any path, signed with this store's token. On POST, body: goes in the form body.
    # One call, one request.
    def request(http_method, path, query: nil, body: nil, idempotent: nil)
      @session.request(http_method, path, query:, body:, idempotent:)
    end

    def inspect
      "#<#{self.class.name} access_token=#{Redaction::REDACTED}>"
    end

    private

    def build_resources
      @categories = Categories.new(@session)
      @brands = Brands.new(@session)
      @media = Media.new(@session)
      @products = Products.new(@session)
      @stock = Stock.new(@session)
      @prices = Prices.new(@session)
      @orders = Orders.new(@session)
    end
  end
end
