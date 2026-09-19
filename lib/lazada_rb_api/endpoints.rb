# frozen_string_literal: true

module LazadaRbApi
  # The named hosts, and the only place in this gem that spells out a host. Hosts are configuration, not code:
  # pick one with Client.new(endpoint:), or pass base_url: / auth_base_url: / token_base_url: for any other host.
  #
  # api:   the API host of one country (https://open.lazada.com/apps/doc/doc?nodeId=10400&docId=108065). A token
  #        belongs to one country and works only against that country's host ("Tokens are not interchangeable
  #        across sites"), so pick the endpoint that matches the credential.
  # auth:  the seller consent page host, shared by every country (/oauth/authorize).
  # token: the token API host, shared by every country (/auth/token/create and /auth/token/refresh).
  ENDPOINTS = {
    ph: { api: "https://api.lazada.com.ph/rest", auth: "https://auth.lazada.com",
          token: "https://auth.lazada.com/rest" }.freeze,
    my: { api: "https://api.lazada.com.my/rest", auth: "https://auth.lazada.com",
          token: "https://auth.lazada.com/rest" }.freeze,
    sg: { api: "https://api.lazada.sg/rest", auth: "https://auth.lazada.com",
          token: "https://auth.lazada.com/rest" }.freeze,
    th: { api: "https://api.lazada.co.th/rest", auth: "https://auth.lazada.com",
          token: "https://auth.lazada.com/rest" }.freeze,
    vn: { api: "https://api.lazada.vn/rest", auth: "https://auth.lazada.com",
          token: "https://auth.lazada.com/rest" }.freeze,
    id: { api: "https://api.lazada.co.id/rest", auth: "https://auth.lazada.com",
          token: "https://auth.lazada.com/rest" }.freeze
  }.freeze

  module Endpoints
    # The endpoint used when Client.new gets no endpoint:. Change it here, and only here.
    DEFAULT = :ph

    AUTHORIZE_PAGE = "/oauth/authorize"

    TOKEN_CREATE = "/auth/token/create"
    TOKEN_REFRESH = "/auth/token/refresh"

    SELLER = "/seller/get"
    PRE_QC_RULES = "/product/seller/item/getPreQcRules"
    SELLER_ITEM_LIMIT = "/product/seller/item/limit"

    CATEGORY_TREE = "/category/tree/get"
    CATEGORY_ATTRIBUTES = "/category/attributes/get"
    CATEGORY_SUGGESTION = "/product/category/suggestion/get"
    BRANDS = "/category/brands/query"
    IMAGE_UPLOAD = "/image/upload"

    PRODUCT_CREATE = "/product/create"
    PRODUCT_ITEM = "/product/item/get"
    PRODUCT_UPDATE = "/product/update"
    PRODUCTS = "/products/get"
    PRODUCT_DEACTIVATE = "/product/deactivate"
    PRODUCT_STATUS = "/product/global/update/status"
    QC_ALERTS = "/product/qc/alert/list"
    PRICE_QUANTITY = "/product/price_quantity/update"

    ORDERS = "/orders/get"
    ORDER = "/order/get"
    ORDER_ITEMS = "/order/items/get"
  end
  private_constant :Endpoints
end
