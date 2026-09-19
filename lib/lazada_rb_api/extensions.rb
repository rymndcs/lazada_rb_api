# frozen_string_literal: true

module LazadaRbApi
  # This gem's declared platform extensions (CONTRACT.md "Declared platform extensions"): public surface beyond the
  # shared contract. "Class#member" => what it calls. The conformance suite fails on any public method or constant
  # that is neither in the contract nor declared here.
  EXTENSIONS = {
    "Products#qc_alerts" => "GET /product/qc/alert/list",
    "Products#activate_skus" => "POST /product/update with each SKU's Status \"active\" (local-seller reactivation)",
    "Orders#items" => "GET /order/items/get",
    "Shop#item_limit" => "GET /product/seller/item/limit (GetSellerItemLimit)"
  }.freeze
end
