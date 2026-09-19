# frozen_string_literal: true

# The shared interface contract (CONTRACT.md) as data. Shared verbatim by shopee_rb_api, lazada_rb_api and
# tiktok_shop_rb_api; it never names a platform. Changing the contract means changing this file, CONTRACT.md and
# CONTRACT_VERSION in all three gems in one sitting, then rewriting test/conformance/MANIFEST.
module Conformance
  REST = [%i[keyrest params]].freeze
  REQUEST = [%i[req http_method], %i[req path], %i[key query], %i[key body], %i[key idempotent]].freeze
  PAGED = [%i[key page_size], %i[key cursor], %i[keyrest params]].freeze

  CONTRACT = {
    version: "2",

    module_constants: %i[
      VERSION CONTRACT_VERSION EXTENSIONS ENDPOINTS
      Client Shop Auth Grant AuthorizedShop Response ItemError Page Pager RetryPolicy Webhook WebhookEvent Transport
      Categories Brands Media Products Stock Prices Orders
      Error ConfigurationError TransportError PaginationLimitError WebhookSignatureError ApiError
      AuthenticationError AppCredentialsError PermissionError SignatureError RateLimitError QuotaExceededError
      ConcurrencyError ServerError RequestError BusinessError
    ],

    # Class => constants that must exist on it.
    class_constants: {
      "Shop" => %i[LOCATOR_KEYS],
      "Products" => %i[UNLIST_BATCH_MAX RELIST_BATCH_MAX]
    },

    # Class => { initialize: params, singleton: { name => params }, instance: { name => params } }.
    # `instance` is the exact list of public methods the class itself defines, besides declared extensions.
    # `initialize` is the exact parameter list in order, except that a class may also take optional keywords that its
    # EXTENSIONS declare as "Class#keyword", each with a public reader of the same name (surface_test.rb).
    classes: {
      "Client" => {
        initialize: [%i[keyreq app_key], %i[keyreq app_secret], %i[key endpoint], %i[key base_url],
                     %i[key auth_base_url], %i[key transport], %i[key clock], %i[key logger],
                     %i[key retry_policy]],
        instance: {
          app_key: [], endpoint: [], auth: [],
          shop: [%i[keyreq access_token], %i[keyrest locator]],
          authorized_shops: [%i[key access_token]],
          verify_webhook: [%i[keyreq raw_body], %i[keyreq signature], %i[key url]],
          request: REQUEST, inspect: []
        }
      },
      "Auth" => {
        instance: {
          authorize_url: [%i[key redirect_uri], %i[key state]],
          exchange_code: [%i[keyreq code], %i[keyrest locator]],
          refresh: [%i[keyreq refresh_token], %i[keyrest locator]],
          inspect: []
        }
      },
      "Shop" => {
        instance: {
          locator: [], info: [], limits: REST,
          categories: [], brands: [], media: [], products: [], stock: [], prices: [], orders: [],
          request: REQUEST, inspect: []
        }
      },
      "Categories" => {
        instance: {
          list: REST, attributes: [%i[req category_id], *REST], recommend: [%i[keyreq title], *REST]
        }
      },
      "Brands" => { instance: { list: [%i[key category_id], *PAGED] } },
      "Media" => { instance: { upload_image: [%i[req io], %i[key filename], *REST] } },
      "Products" => {
        instance: {
          create: [%i[req payload], *REST],
          get: [%i[req product_id], *REST],
          update: [%i[req product_id], %i[req payload], *REST],
          list: PAGED,
          find_by_seller_sku: [%i[req seller_sku]],
          unlist: [%i[req product_ids]],
          relist: [%i[req product_ids]]
        }
      },
      "Stock" => { instance: { get: [%i[req product_id], *REST], update: [%i[req product_id], %i[req skus]] } },
      "Prices" => { instance: { update: [%i[req product_id], %i[req skus]] } },
      "Orders" => { instance: { list: PAGED, get: [%i[req order_id], *REST] } },
      "Pager" => { instance: { each: [%i[block block]], each_page: [], first_page: [] } },
      "RetryPolicy" => {
        initialize: [%i[key max_retries], %i[key base], %i[key cap], %i[key jitter], %i[key sleeper]],
        singleton: { none: [] },
        instance: { max_retries: [], delay_for: [%i[req error], %i[req attempt]], run: [] }
      },
      "Webhook" => {
        singleton: {
          verify: [%i[keyreq raw_body], %i[keyreq signature], %i[keyreq app_key], %i[keyreq app_secret],
                   %i[key url]],
          parse: [%i[req raw_body]]
        },
        instance: {}
      },
      "Transport::NetHttp" => {
        initialize: [%i[key open_timeout], %i[key read_timeout]],
        instance: { call: [%i[keyreq method], %i[keyreq url], %i[keyreq headers], %i[keyreq body]] }
      }
    },

    # Data classes => members.
    data: {
      "Grant" => %i[access_token refresh_token access_token_expires_at refresh_token_expires_at shop_ids raw],
      "AuthorizedShop" => %i[shop_id name region authorization_expires_at locator raw],
      "Response" => %i[data request_id warnings item_errors http_status endpoint raw],
      "ItemError" => %i[id code message raw],
      "Page" => %i[items next_cursor total response],
      "WebhookEvent" => %i[type code shop_id occurred_at data raw]
    },

    # Error class => superclass.
    errors: {
      "Error" => "StandardError",
      "ConfigurationError" => "Error", "TransportError" => "Error", "PaginationLimitError" => "Error",
      "WebhookSignatureError" => "Error", "ApiError" => "Error",
      "AuthenticationError" => "ApiError", "AppCredentialsError" => "ApiError", "PermissionError" => "ApiError",
      "SignatureError" => "ApiError", "RateLimitError" => "ApiError", "QuotaExceededError" => "ApiError",
      "ConcurrencyError" => "ApiError", "ServerError" => "ApiError", "RequestError" => "ApiError",
      "BusinessError" => "ApiError"
    },

    api_error_methods: %i[code message request_id http_status endpoint detail response retry_after retryable?],

    webhook_types: %i[authorization_expiring deauthorized product_status other],

    # The shared calls that obtain tokens. They reach the endpoint's :token host when ENDPOINTS carries one (with
    # the declared Client#token_base_url override), else the API host (hosts_test.rb).
    token_calls: %w[auth.exchange_code auth.refresh],

    # Every shared method that makes a request; the adapter must supply a call for each (requests_test.rb).
    shared_calls: %w[
      auth.exchange_code auth.refresh client.authorized_shops client.request
      shop.info shop.limits shop.request
      categories.list categories.attributes categories.recommend brands.list media.upload_image
      products.create products.get products.update products.list products.find_by_seller_sku products.unlist
      products.relist stock.get stock.update prices.update orders.list orders.get
    ],

    # The shared writes and whether each is idempotent (CONTRACT.md "Errors and retry semantics").
    write_idempotency: {
      "products.create" => false, "products.update" => false, "media.upload_image" => false,
      "products.unlist" => true, "products.relist" => true, "stock.update" => true, "prices.update" => true
    },

    batch_constants: { "products.unlist" => :UNLIST_BATCH_MAX, "products.relist" => :RELIST_BATCH_MAX }
  }.freeze
end
