# frozen_string_literal: true

require "openssl"
require "stringio"

# The Lazada half of the conformance suite: everything platform-specific the shared tests in test/conformance/ need.
# See test/conformance/helper.rb for the interface.
module ConformanceAdapter
  # APP_KEY and APP_SECRET are the example credentials of the push guide
  # (https://open.lazada.com/apps/doc/doc?nodeId=29524&docId=120168). The signing vector's own key and secret are in
  # SIGNING_VECTOR. The tokens, code and ids come from the /auth/token/create and /auth/token/refresh samples.
  APP_KEY = "123456"
  APP_SECRET = "3412gyo124goi3124"
  ACCESS_TOKEN = "50000601c30atpedfgu3LVvik87Ixlsvle3mSoB7701ceb156fPunYZ43GBg"
  REFRESH_TOKEN = "50001600212wcwiOabwyjtEH11acc19aBOvQr9ZYkYDlr987D8BB88LIB8bj"
  AUTH_CODE = "0_100132_2DL4DV3jcU1UOT7WGI1A4rY91"
  # The signing vector's timestamp, 1517820392000 ms.
  FIXED_TIME = Time.at(1_517_820_392).utc
  ITEM_ID = 234_222_211
  SKU_ID = 314_525_867

  module_function

  def gem_module
    LazadaRbApi
  end

  def gem_name
    "lazada_rb_api"
  end

  def fixed_time
    FIXED_TIME
  end

  def build_client(transport:, clock: nil, logger: nil, retry_policy: nil, **)
    LazadaRbApi::Client.new(app_key: APP_KEY, app_secret: APP_SECRET, transport:, clock: clock || -> { FIXED_TIME },
                            logger:, retry_policy: retry_policy || LazadaRbApi::RetryPolicy.none, **)
  end

  def locator
    {}
  end

  def build_shop(client)
    client.shop(access_token: ACCESS_TOKEN, **locator)
  end

  def secrets
    tokens = %w[auth_token_create auth_token_refresh].flat_map do |name|
      Fixtures.body(name).values_at("access_token", "refresh_token")
    end
    [APP_SECRET, ACCESS_TOKEN, REFRESH_TOKEN, AUTH_CODE, *tokens].uniq
  end

  def authorize(client)
    client.auth.authorize_url(redirect_uri: "https://wms.example/online/lazada/callback", state: "csrf-token")
  end

  def read_call
    ->(_client, shop) { shop.info }
  end

  def read_success_response
    Fixtures.response("seller_get")
  end

  REQUEST_ID = "0ba2887315178178017221014"

  # The documented error envelope (doc 108138): type, code, message, request_id and sometimes detail[].
  def error(code, message, type: "ISV", detail: nil, status: 200)
    body = { "type" => type, "code" => code, "message" => message, "request_id" => REQUEST_ID }
    body["detail"] = detail if detail
    FakeTransport.json(body, status:)
  end

  def server_error_response
    error("1000", "Internal Application Error", type: "ISP")
  end

  def rate_limit_response
    error("901", "Limit service request speed in server side temporarily.", type: "SYSTEM")
  end

  def unmapped_error_response
    error("NotDocumentedAnywhere", "A code the error table has never seen.")
  end

  def error_samples
    detail = [{ "field" => "SellerSku", "message" => "SellerSku repeat" }]
    [
      ["AuthenticationError", "IllegalAccessToken", "The specified access token is invalid or expired", false],
      ["PermissionError", "SellerNotActive", "Seller not active,please check seller status", false],
      ["PermissionError", "InsufficientPermission", "App does not have permission to call this API", false],
      ["PermissionError", "E0501", "SELLER_NOT_PERMITTED", false],
      ["SignatureError", "IncompleteSignature", "The request signature does not conform to lazop standards", false],
      ["SignatureError", "MissingParameter", "the input parameter “sign” that is mandatory for processing this " \
                                             "request is not supplied", false],
      ["RequestError", "5", "E005: Invalid Request Format", false],
      ["RateLimitError", "901", "Limit service request speed in server side temporarily.", true, :positive],
      ["RateLimitError", "ApiCallLimit", "API-level global rate limit", true],
      ["ConcurrencyError", "4147", "THD_IC_ERR_F_IC_SERVICE_EDIT_002", true],
      ["ServerError", "1000", "Internal Application Error", true],
      ["ServerError", "501", "Update product failed", true],
      ["BusinessError", "501", "Update product failed", false, nil, detail],
      ["BusinessError", "4148", "BIZ_CHECK_ITEM_HAS_REACH_LIMIT", false]
    ].map do |class_name, code, message, retryable, retry_after, error_detail|
      { class_name:, response: error(code, message, detail: error_detail), code:, request_id: REQUEST_ID,
        retryable:, retry_after: }
    end
  end

  # Lazada documents no invalid-app-key code and no daily-quota code (the FAQ describes a ban of about 14 hours
  # without naming its code), so neither class is sampled.
  def error_classes_without_platform_code
    %w[AppCredentialsError QuotaExceededError]
  end

  def image
    StringIO.new("\xFF\xD8\xFFjpeg".b)
  end

  def shared_calls
    {
      "auth.exchange_code" => [->(c, _) { c.auth.exchange_code(code: AUTH_CODE) }, "auth_token_create"],
      "auth.refresh" => [->(c, _) { c.auth.refresh(refresh_token: REFRESH_TOKEN) }, "auth_token_refresh"],
      "client.authorized_shops" => [->(c, _) { c.authorized_shops(access_token: ACCESS_TOKEN) }, "seller_get"],
      "client.request" => [->(c, _) { c.request(:get, "/category/tree/get", query: { language_code: "en_US" }) },
                           "category_tree_get"],
      "shop.info" => [->(_, s) { s.info }, "seller_get"],
      "shop.limits" => [->(_, s) { s.limits(option: 1, option_set: [1, 2]) }, "product_seller_item_getPreQcRules"],
      "shop.request" => [->(_, s) { s.request(:get, "/product/item/get", query: { item_id: ITEM_ID }) },
                         "product_item_get"],
      "categories.list" => [->(_, s) { s.categories.list(language_code: "en_US") }, "category_tree_get"],
      "categories.attributes" => [->(_, s) { s.categories.attributes(8704) }, "category_attributes_get"],
      "categories.recommend" => [lambda { |_, s|
        s.categories.recommend(title: "Man T-Shirt Summer", image_url: "https://example.test/tshirt.png")
      }, "product_category_suggestion_get"],
      "brands.list" => [->(_, s) { s.brands.list }, "category_brands_query"],
      "media.upload_image" => [->(_, s) { s.media.upload_image(image, filename: "a.jpg") }, "image_upload"],
      "products.create" => [->(_, s) { s.products.create(product_payload) }, "product_create"],
      "products.get" => [->(_, s) { s.products.get(ITEM_ID) }, "product_item_get"],
      "products.update" => [lambda { |_, s|
        s.products.update(ITEM_ID, { "Attributes" => { "name" => "H4 bulb" }, "Skus" => { "Sku" => [{ "SkuId" => SKU_ID }] } })
      }, "product_update"],
      "products.list" => [->(_, s) { s.products.list(filter: "live") }, "products_get"],
      "products.find_by_seller_sku" => [->(_, s) { s.products.find_by_seller_sku("39817:01:01") }, "products_get"],
      "products.unlist" => [->(_, s) { s.products.unlist([ITEM_ID]) }, "product_deactivate"],
      "products.relist" => [->(_, s) { s.products.relist([3_042_450_256]) }, "product_global_update_status"],
      "stock.get" => [->(_, s) { s.stock.get(ITEM_ID) }, "product_item_get"],
      "stock.update" => [->(_, s) { s.stock.update(ITEM_ID, [{ "SkuId" => SKU_ID, "Quantity" => 20 }]) },
                         "product_price_quantity_update"],
      "prices.update" => [->(_, s) { s.prices.update(ITEM_ID, [{ "SkuId" => SKU_ID, "Price" => "1099.00" }]) },
                          "product_price_quantity_update"],
      "orders.list" => [->(_, s) { s.orders.list(created_after: "2018-02-10T09:00:00+08:00") }, "orders_get"],
      "orders.get" => [->(_, s) { s.orders.get(491_253_082_180_001) }, "order_get"]
    }.map { |name, (call, fixture)| { name:, call:, response: Fixtures.response(fixture) } }
  end

  def product_payload
    { "PrimaryCategory" => "10002019", "Images" => { "Image" => ["https://my-live-02.slatic.net/p/a.jpg"] },
      "Attributes" => { "name" => "H4 bulb", "brand_id" => "30768" },
      "Skus" => { "Sku" => [{ "SellerSku" => "OT405", "quantity" => "3", "price" => "35", "package_height" => "10",
                              "package_length" => "10", "package_width" => "10", "package_weight" => "0.5" }] } }
  end

  def write_calls
    names = Conformance::CONTRACT[:write_idempotency].keys
    shared_calls.select { |c| names.include?(c[:name]) }.map do |c|
      c.merge(call: ->(shop) { c[:call].call(nil, shop) })
    end
  end

  def batch_calls
    [
      { name: "products.unlist", call: ->(shop, ids) { shop.products.unlist(ids) } },
      { name: "products.relist", call: ->(shop, ids) { shop.products.relist(ids) } }
    ]
  end

  def envelope_samples
    status = Fixtures.body("product_global_update_status")
    seller = Fixtures.body("seller_get")
    rules = Fixtures.body("product_seller_item_getPreQcRules")
    brands = Fixtures.body("category_brands_query")
    limit = Fixtures.body("product_seller_item_limit")
    tree = Fixtures.body("category_tree_get")
    failure = status["data"]["update_ic_product_fail_result_list"].first
    [
      { name: "success / error_code envelope with per-product failures",
        call: ->(_, s) { s.products.relist([3_042_450_256]) },
        response: Fixtures.response("product_global_update_status"),
        expect: { data: status["data"], request_id: status["request_id"], warnings: [],
                  item_errors: [["3042450256", "", failure["update_msg"]]] } },
      { name: "payload under data", call: ->(_, s) { s.info }, response: Fixtures.response("seller_get"),
        expect: { data: seller["data"], request_id: seller["request_id"], warnings: [], item_errors: [] } },
      { name: "payload under values", call: ->(_, s) { s.limits(option: 1, option_set: [1, 2]) },
        response: Fixtures.response("product_seller_item_getPreQcRules"),
        expect: { data: rules["values"], request_id: rules["request_id"], warnings: [], item_errors: [] } },
      { name: "brands envelope (success / error_code / error_msg)", call: ->(_, s) { s.brands.list.first_page.response },
        response: Fixtures.response("category_brands_query"),
        expect: { data: brands["data"], request_id: brands["request_id"], warnings: [], item_errors: [] } },
      { name: "seller limit envelope (success / errorCodes / errorMsgs)", call: ->(_, s) { s.item_limit },
        response: Fixtures.response("product_seller_item_limit"),
        expect: { data: limit["data"], request_id: limit["request_id"], warnings: [], item_errors: [] } },
      { name: "data is an Array", call: ->(_, s) { s.categories.list },
        response: Fixtures.response("category_tree_get"),
        expect: { data: tree["data"], request_id: tree["request_id"], warnings: [], item_errors: [] } }
    ]
  end

  def uncoerced_sample
    { call: ->(_, s) { s.products.get(ITEM_ID) }, response: Fixtures.response("product_item_get"),
      checks: [[%w[item_id], "234222211"], [["skus", 0, "price"], 32], [["skus", 0, "package_width"], "10.00"],
               [["skus", 0, "SkuId"], 314_525_867], [%w[trialProduct], "true,false"]] }
  end

  # One page of a Lazada list response built from a fixture: `path` names the items inside data, and `fields`
  # replaces (or, with :absent, removes) members of data.
  def page_of(fixture, items_key, items, **fields)
    body = Fixtures.body(fixture)
    if body["data"].is_a?(Array)
      body = body.merge("data" => items)
    else
      data = body["data"].merge(items_key => items)
      fields.each { |k, v| v == :absent ? data.delete(k.to_s) : data[k.to_s] = v }
      data.delete(items_key) if items == :absent
      body = body.merge("data" => data)
    end
    FakeTransport.json(body)
  end

  def pagers
    [products_pager, brands_pager, orders_pager, qc_alerts_pager]
  end

  def numbered(key, from, count)
    Array.new(count) { |i| { key => (from + i).to_s } }
  end

  def products_pager
    f = "products_get"
    full = ->(from) { page_of(f, "products", numbered("item_id", from, 50)) }
    { name: "products.list", page_size_key: :limit, max_page_size: 50,
      call: ->(_, s, **o) { s.products.list(filter: "all", page_size: o.delete(:limit), **o) },
      pages: [full[1], full[51], page_of(f, "products", numbered("item_id", 101, 7))],
      final_variants: [page_of(f, "products", numbered("item_id", 51, 3)), page_of(f, "products", :absent)],
      cap: { responses: Array.new(201) { |i| full[(i * 50) + 1] } } }
  end

  def brands_pager
    f = "category_brands_query"
    { name: "brands.list", page_size_key: :pageSize, max_page_size: 200,
      call: ->(_, s, **o) { s.brands.list(page_size: o.delete(:pageSize), **o) },
      pages: [page_of(f, "module", numbered("brand_id", 1, 200), total_record: "405"),
              page_of(f, "module", numbered("brand_id", 201, 200), total_record: "405"),
              page_of(f, "module", numbered("brand_id", 401, 5), total_record: "405")],
      final_variants: [page_of(f, "module", numbered("brand_id", 201, 200), total_record: "400"),
                       page_of(f, "module", [], total_record: "405")] }
  end

  def orders_pager
    f = "orders_get"
    { name: "orders.list", page_size_key: :limit, max_page_size: 100,
      call: lambda { |_, s, **o|
        s.orders.list(created_after: "2018-02-10T09:00:00+08:00", page_size: o.delete(:limit), **o)
      },
      pages: [page_of(f, "orders", numbered("order_id", 1, 100), countTotal: "203"),
              page_of(f, "orders", numbered("order_id", 101, 100), countTotal: "203"),
              page_of(f, "orders", numbered("order_id", 201, 3), countTotal: "203")],
      final_variants: [page_of(f, "orders", numbered("order_id", 101, 100), countTotal: "200"),
                       page_of(f, "orders", :absent, countTotal: :absent)] }
  end

  def qc_alerts_pager
    f = "product_qc_alert_list"
    { name: "products.qc_alerts", page_size_key: :limit, max_page_size: nil,
      call: ->(_, s, **o) { s.products.qc_alerts(page_size: o.delete(:limit), **o) },
      pages: [page_of(f, nil, numbered("productId", 1, 50)), page_of(f, nil, numbered("productId", 51, 50)),
              page_of(f, nil, numbered("productId", 101, 1))],
      final_variants: [page_of(f, nil, numbered("productId", 51, 2)), page_of(f, nil, [])] }
  end

  # The same request, whatever its timestamp and signature.
  def request_identity(request)
    [request.http_method, request.path, request.query.except("sign", "timestamp"), request.body]
  end

  def signer
    LazadaRbApi.const_get(:Signer)
  end

  # The official vector of https://open.lazada.com/apps/doc/doc?nodeId=10400&docId=108069.
  SIGNING_VECTOR = {
    path: "/order/get", secret: "helloworld",
    params: { "access_token" => "test", "app_key" => "123456", "order_id" => "1234", "sign_method" => "sha256",
              "timestamp" => "1517820392000" }
  }.freeze

  def signing_vectors
    base = signer.base_string(SIGNING_VECTOR[:path], SIGNING_VECTOR[:params])
    [{ name: "doc 108069 /order/get", base_string: base, signature: signer.sign(SIGNING_VECTOR[:secret], base),
       expected_base_string: "/order/getaccess_tokentestapp_key123456order_id1234sign_methodsha256" \
                             "timestamp1517820392000",
       expected_signature: "4190D32361CFB9581350222F345CB77F3B19F0E31D162316848A2C1FFD5FAB4A" }]
  end

  def signed_calls
    tokenless = %w[auth.exchange_code categories.list]
    names = %w[shop.info client.authorized_shops products.create media.upload_image auth.exchange_code
               categories.list orders.list]
    shared_calls.select { |c| names.include?(c[:name]) }.map do |c|
      c.merge(token: tokenless.include?(c[:name]) ? nil : ACCESS_TOKEN)
    end
  end

  def signature_parts(request)
    query = request.query
    { signature: query["sign"], timestamp: Integer(query["timestamp"]), access_token: query["access_token"] }
  end

  # Recomputed from the request as sent, following doc 108068 directly rather than the gem's Signer: every query
  # and form parameter but sign (and not the file part), sorted by name, after the API path (the URL path without
  # the /rest prefix).
  def expected_signature(request)
    params = request.query_pairs.reject { |k, _| k == "sign" } + form_pairs(request)
    raise "app_key missing from the query" unless request.query["app_key"] == APP_KEY

    base = request.path.delete_prefix("/rest") + params.sort_by(&:first).map { |k, v| "#{k}#{v}" }.join
    OpenSSL::HMAC.hexdigest("SHA256", APP_SECRET, base).upcase
  end

  def form_pairs(request)
    type = request.header("Content-Type").to_s
    return URI.decode_www_form(request.body.to_s) if type.start_with?("application/x-www-form-urlencoded")
    return [] unless type.start_with?("multipart/form-data")

    boundary = type[/boundary=(.+)\z/, 1]
    request.body.split("--#{boundary}").filter_map do |part|
      next if part.include?("filename=")

      name = part[/name="([^"]+)"/, 1]
      [name, part.split("\r\n\r\n", 2).last.chomp("\r\n")] if name
    end
  end

  def timestamp_for(time)
    (time.to_r * 1000).floor
  end

  # Lazada signs form parameters, not the body bytes.
  def signed_body(_request)
    nil
  end

  def webhook_credentials
    { app_key: APP_KEY, app_secret: APP_SECRET }
  end

  def webhook_url_required?
    false
  end

  EXPIRY_PUSH = '{"seller_id":"null","message_type":8,"data":{"app_key":"123456","auth_expiry_time":1627542238,' \
                '"seller_id":"1000165972"},"timestamp":1627416758,"site":"lazada_ph"}'
  QC_PUSH = '{"seller_id":"500176629136","message_type":1,"data":{"date":1627451616614,"itemId":2202832065,' \
            '"reason":"Prohibited and Controlled Products Policy","seller_id":500176629136,"status":"Lock"},' \
            '"timestamp":1627451616,"site":"lazada_ph"}'

  # SELF-GENERATED vectors: the push guide's own example (signature f3d2ca94…6104ab) cannot be reproduced, because
  # its body is elided as {...}. These use the guide's example app key and secret over the documented token-expiry
  # and QC bodies; the digests were derived with Python's hmac module, independently of the gem.
  def webhook_vectors
    [
      { name: "token expiration alert (msg_type 8), self-generated", url: nil, raw_body: EXPIRY_PUSH,
        signature: "db0ff45c239239076b916c2d1e190ea65ea591bb7427ba473ba766bb1f5d06a3" },
      { name: "product QC status (msg_type 1), self-generated", url: nil, raw_body: QC_PUSH,
        signature: "741b801927ca2ef96c5e86870b113f8acee862193d8da6ec8a4471bef999ab53" }
    ]
  end

  def webhook_parse_samples
    [
      { raw_body: EXPIRY_PUSH,
        expect: { type: :authorization_expiring, code: "8", shop_id: "1000165972",
                  occurred_at: Time.at(1_627_416_758).utc } },
      { raw_body: QC_PUSH,
        expect: { type: :product_status, code: "1", shop_id: "500176629136", occurred_at: Time.at(1_627_451_616).utc } },
      { raw_body: '{"seller_id":"1234567","message_type":0,"data":{"order_status":"unpaid",' \
                  '"trade_order_id":"260422900198363"},"timestamp":1603766859530,"site":"lazada_vn"}',
        expect: { type: :other, code: "0", shop_id: "1234567", occurred_at: Time.at(1_603_766_859.53r).utc } }
    ]
  end

  def token_samples
    create = Fixtures.body("auth_token_create")
    refresh = Fixtures.body("auth_token_refresh")
    [
      { name: "exchange_code", call: ->(c) { c.auth.exchange_code(code: AUTH_CODE) },
        response: Fixtures.response("auth_token_create"),
        expect: { access_token: create["access_token"], refresh_token: create["refresh_token"],
                  access_expires_in: 10, refresh_expires_in: 60, shop_ids: %w[1001] } },
      { name: "refresh", call: ->(c) { c.auth.refresh(refresh_token: REFRESH_TOKEN) },
        response: Fixtures.response("auth_token_refresh"),
        expect: { access_token: refresh["access_token"], refresh_token: refresh["refresh_token"],
                  access_expires_in: 10, refresh_expires_in: 60, shop_ids: %w[1001] } }
    ]
  end

  def extension_files
    []
  end
end
