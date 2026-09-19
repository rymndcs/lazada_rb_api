# frozen_string_literal: true

# Wire-shape tests check several fields of one request, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

# The method, path, query and body each wrapped endpoint sends, per its official doc page.
class ResourcesTest < Minitest::Test
  include UnitHelper

  def assert_get(request, path, query, access_token = A::ACCESS_TOKEN)
    assert_equal :get, request.http_method
    assert_equal "/rest#{path}", request.path
    assert_nil request.body
    query.each { |key, value| assert_equal value, request.query[key], key }
    access_token ? assert_equal(access_token, request.query["access_token"]) : assert_nil(request.query["access_token"])
  end

  def assert_post(request, path, body)
    assert_equal :post, request.http_method
    assert_equal "/rest#{path}", request.path
    assert_equal A::ACCESS_TOKEN, request.query["access_token"]
    assert_equal body, form(request)
  end

  def json(value)
    JSON.generate(value)
  end

  def test_info_and_both_limit_endpoints
    assert_get(request_for(&:info), "/seller/get", {})
    assert_get(request_for { |s| s.limits(option: 1, option_set: [1, 2]) }, "/product/seller/item/getPreQcRules",
               "option" => "1", "option_set" => "[1,2]")
    assert_get(request_for(&:item_limit), "/product/seller/item/limit", {})
  end

  def test_catalogue_reads_without_authorization_send_no_token
    assert_get(request_for { |s| s.categories.list(language_code: "en_US") }, "/category/tree/get",
               { "language_code" => "en_US" }, nil)
    assert_get(request_for { |s| s.categories.attributes("8704", language_code: "en_US") },
               "/category/attributes/get", { "primary_category_id" => "8704" }, nil)
    assert_get(request_for(Fixtures.response("category_brands_query")) { |s| s.brands.list(page_size: 20).first_page },
               "/category/brands/query", { "startRow" => "0", "pageSize" => "20" }, nil)
  end

  def test_category_suggestion_is_authorized
    assert_get(request_for { |s| s.categories.recommend(title: "Man T-Shirt", image_url: "https://x.test/a.png") },
               "/product/category/suggestion/get", "product_name" => "Man T-Shirt",
                                                   "image_url" => "https://x.test/a.png")
  end

  def test_brands_are_per_region
    shop, transport = shop_with

    assert_raises(ArgumentError) { shop.brands.list(category_id: 1) }
    assert_raises(ArgumentError) { shop.brands.list(page_size: 201) }
    assert_empty transport.requests
  end

  def test_products_create_wraps_the_request_node
    product = { "PrimaryCategory" => "10002019", "Skus" => { "Sku" => [{ "SellerSku" => "OT405" }] } }

    assert_post(request_for(Fixtures.response("product_create")) { |s| s.products.create(product) },
                "/product/create", "payload" => json("Request" => { "Product" => product }))
  end

  def test_products_update_sets_item_id
    payload = { "Attributes" => {}, "Skus" => { "Sku" => [{ "SkuId" => "1", "price" => "35" }] } }

    assert_post(request_for { |s| s.products.update("234222211", payload) }, "/product/update",
                "payload" => json("Request" => { "Product" => payload.merge("ItemId" => "234222211") }))
  end

  def test_products_get_and_stock_get
    assert_get(request_for { |s| s.products.get("234222211") }, "/product/item/get", "item_id" => "234222211")
    assert_get(request_for { |s| s.stock.get(234_222_211) }, "/product/item/get", "item_id" => "234222211")
    assert_raises(ArgumentError) { request_for { |s| s.products.get("sku-1") } }
  end

  def test_products_list_pages_by_offset_and_carries_total_products
    shop, transport = shop_with(Fixtures.response("products_get"))
    page = shop.products.list(filter: "live", update_after: "2026-09-01T00:00:00+08:00", page_size: 1).first_page

    assert_get(transport.requests.first, "/products/get", "filter" => "live", "limit" => "1", "offset" => "0",
                                                          "update_after" => "2026-09-01T00:00:00+08:00")
    assert_equal "10", page.total
    assert_equal "1", page.next_cursor
    assert_equal(["180226526"], page.items.map { |p| p["item_id"] })
  end

  def test_find_by_seller_sku
    shop, transport = shop_with(Fixtures.response("products_get"))

    assert_equal ["180226526"], shop.products.find_by_seller_sku("39817:01:01")
    assert_get(transport.requests.first, "/products/get", "filter" => "all", "sku_seller_list" => '["39817:01:01"]',
                                                          "limit" => "50")
  end

  def test_unlist_deactivates_one_item
    assert_post(request_for { |s| s.products.unlist(["234222211"]) }, "/product/deactivate",
                "apiRequestBody" => json("Request" => { "Product" => { "ItemId" => "234222211" } }))
  end

  def test_relist_is_the_cross_border_up_shelf_call_for_the_endpoints_country
    shop, transport = shop_with(Fixtures.response("product_global_update_status"), endpoint: :my)
    response = shop.products.relist([3_042_450_256])

    assert_post(transport.requests.first, "/product/global/update/status",
                "type" => "single", "country" => "MY", "product_id" => "3042450256", "status" => "upShelf")
    assert_equal ["3042450256"], response.item_errors.map(&:id)
  end

  def test_activate_skus_sets_each_sku_status_active
    request = request_for { |s| s.products.activate_skus(234_222_211, [1, "2"]) }
    product = { "ItemId" => "234222211", "Attributes" => {},
                "Skus" => { "Sku" => [{ "SkuId" => "1", "Status" => "active" },
                                      { "SkuId" => "2", "Status" => "active" }] } }

    assert_post(request, "/product/update", "payload" => json("Request" => { "Product" => product }))
    assert_raises(ArgumentError) { request_for { |s| s.products.activate_skus(1, []) } }
  end

  def test_qc_alerts_pages_by_offset
    shop, transport = shop_with(Fixtures.response("product_qc_alert_list"))
    page = shop.products.qc_alerts(page_size: 10).first_page

    assert_get(transport.requests.first, "/product/qc/alert/list", "offset" => "0", "limit" => "10")
    assert_nil page.next_cursor
    assert_equal(["0"], page.items.map { |a| a["productId"] })
  end

  def test_stock_and_price_updates_set_item_id_on_every_sku
    stock = request_for { |s| s.stock.update(234, [{ "SkuId" => "1", "Quantity" => 20 }]) }
    price = request_for { |s| s.prices.update("234", [{ SkuId: "1", Price: "1099.00", SalePrice: "900.00" }]) }

    skus = ->(sku) { json("Request" => { "Product" => { "Skus" => { "Sku" => [sku] } } }) }

    assert_post(stock, "/product/price_quantity/update",
                "payload" => skus[{ "SkuId" => "1", "Quantity" => 20, "ItemId" => "234" }])
    assert_post(price, "/product/price_quantity/update",
                "payload" => skus[{ "SkuId" => "1", "Price" => "1099.00", "SalePrice" => "900.00", "ItemId" => "234" }])
    assert_raises(ArgumentError) { request_for { |s| s.stock.update(1, Array.new(51) { { "SkuId" => "1" } }) } }
  end

  def test_media_upload_is_multipart_with_the_image_part
    request = request_for(Fixtures.response("image_upload")) do |s|
      s.media.upload_image(StringIO.new("\xFF\xD8".b), filename: "bulb.jpg")
    end

    assert_equal "/rest/image/upload", request.path
    assert_match(%r{\Amultipart/form-data; boundary=lazada-rb-api-\h{32}\z}, request.header("Content-Type"))
    assert_includes request.body, "name=\"image\"; filename=\"bulb.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n\xFF\xD8".b
  end

  def test_orders
    shop, transport = shop_with(Fixtures.response("orders_get"))
    page = shop.orders.list(created_after: "2018-02-10T09:00:00+08:00", status: "pending", page_size: 1).first_page

    assert_get(transport.requests.first, "/orders/get", "created_after" => "2018-02-10T09:00:00+08:00",
                                                        "status" => "pending", "limit" => "1", "offset" => "0")
    assert_equal "500", page.total
    assert_equal "1", page.next_cursor
    assert_get(request_for { |s| s.orders.get("491253082180001") }, "/order/get", "order_id" => "491253082180001")
    assert_get(request_for { |s| s.orders.items(491_253_082_180_001) }, "/order/items/get",
               "order_id" => "491253082180001")
  end

  def test_request_escape_hatches
    shop, transport = shop_with(ok, ok)
    shop.request(:post, "/product/remove", body: { sku_id_list: ["SkuId_1_2"] })
    client = A.build_client(transport:)
    transport.push(ok)
    client.request(:get, "/category/tree/get", query: { language_code: "en_US" })

    assert_post(transport.requests.first, "/product/remove", "sku_id_list" => '["SkuId_1_2"]')
    assert_get(transport.requests.last, "/category/tree/get", { "language_code" => "en_US" }, nil)
    assert_raises(ArgumentError) { shop.request(:put, "/product/update") }
  end
end
# rubocop:enable Minitest/MultipleAssertions
