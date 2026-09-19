# frozen_string_literal: true

require_relative "live_helper"

# Phase-0 checks from the Lazada plan (§9) that need a real app and store: the signature is accepted, the read
# endpoints answer in the documented shapes, and which limit endpoint serves this seller. With LAZADA_RECORD=1 each
# response replaces its doc fixture.
class LiveReadsTest < Minitest::Test
  include LiveHelper::Gate

  def shop
    @shop ||= LiveHelper.shop
  end

  def test_signed_call_is_accepted
    info = shop.info

    assert_kind_of String, info.request_id
    assert info.data.key?("seller_id"), "/seller/get names the seller"
  end

  def test_authorized_shops_lists_this_store
    shops = LiveHelper.client.authorized_shops(access_token: ENV.fetch("LAZADA_ACCESS_TOKEN")).to_a

    assert_equal 1, shops.size
  end

  def test_catalogue_reads
    assert_kind_of Array, shop.categories.list(language_code: "en_US").data
    assert_kind_of Array, shop.brands.list(page_size: 20).first_page.items
  end

  # Records what each limit endpoint answers for this seller: GetSellerItemLimit is documented for cross-border
  # sellers only (plan §10 Q2).
  def test_both_limit_endpoints
    assert_kind_of Hash, shop.limits(option: 1, option_set: [1, 2]).data
    begin
      assert_kind_of Hash, shop.item_limit.data
    rescue LazadaRbApi::PermissionError => e
      assert_equal "ONLY_CB_SELLER_SUPPORTED", e.code
    end
  end

  def test_products_first_page
    page = shop.products.list(filter: "live", page_size: 10).first_page

    assert_kind_of Array, page.items
    skip "the store has no live products to read" if page.items.empty?

    item_id = page.items.first["item_id"]

    assert_kind_of Array, shop.products.get(item_id).data["skus"]
  end

  def test_qc_alerts_first_page
    assert_kind_of Array, shop.products.qc_alerts(page_size: 10).first_page.items
  end

  def test_orders_first_page_of_the_last_day
    since = (Time.now - 86_400).strftime("%Y-%m-%dT%H:%M:%S%:z")

    assert_kind_of Array, shop.orders.list(update_after: since, page_size: 10).first_page.items
  end
end
