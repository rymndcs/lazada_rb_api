# frozen_string_literal: true

module LazadaRbApi
  class Products < Resources::Base
    UNLIST_BATCH_MAX = 1
    RELIST_BATCH_MAX = 1
    PAGE_SIZE_MAX = 50
    OFFSET_MAX = 10_000
    QC_ALERTS_PAGE_SIZE = 50
    private_constant :PAGE_SIZE_MAX, :OFFSET_MAX, :QC_ALERTS_PAGE_SIZE

    # POST /product/create. payload is the native Product node (PrimaryCategory, Images, Attributes, Skus, ...);
    # the gem wraps it as {"Request":{"Product":payload}} and sends it as `payload`. Variants travel inside Skus.
    # Not idempotent: Lazada has no idempotency key, and a timed-out create may have landed (look the SellerSku up
    # with find_by_seller_sku before retrying).
    # https://open.lazada.com/apps/doc/api?path=/product/create
    def create(payload, **params)
      session.post(Endpoints::PRODUCT_CREATE, { payload: Resources.product_request(stringify(payload)) }.merge(params))
    end

    # GET /product/item/get with item_id. Carries status, subStatus and rejectReason (the QC outcome).
    # https://open.lazada.com/apps/doc/api?path=/product/item/get
    def get(product_id, **params)
      session.get(Endpoints::PRODUCT_ITEM, { item_id: id!(product_id, "product_id") }.merge(params))
    end

    # POST /product/update: a partial update. The gem sets ItemId; Lazada requires SkuId on every Sku and an
    # Attributes node (it may be empty). Not idempotent.
    # https://open.lazada.com/apps/doc/api?path=/product/update
    def update(product_id, payload, **params)
      product = stringify(payload).merge("ItemId" => id!(product_id, "product_id").to_s)
      session.post(Endpoints::PRODUCT_UPDATE, { payload: Resources.product_request(product) }.merge(params))
    end

    # GET /products/get, offset-paged (offset / limit, at most 50 per page), stopped by a short page. Native
    # params: filter (all, live, inactive, deleted, pending, rejected, sold-out), create_after / update_after and
    # their _before pairs (ISO 8601), options, sku_seller_list. Lazada caps the offset at 10,000; a walk that would
    # pass it raises PaginationLimitError, and narrowing the date window is the caller's job.
    # https://open.lazada.com/apps/doc/api?path=/products/get
    def list(page_size: nil, cursor: nil, **params)
      size = page_size!(page_size, PAGE_SIZE_MAX)
      Pager.new(cursor:) do |next_offset|
        start = offset(next_offset)
        raise PaginationLimitError, "Lazada caps /products/get at offset #{OFFSET_MAX}: narrow the date window" if
          start > OFFSET_MAX

        response = session.get(Endpoints::PRODUCTS, params.merge(limit: size, offset: start))
        data = response.data.is_a?(Hash) ? response.data : {}
        offset_page(response, data["products"], start, size).then { |page| page.with(total: data["total_products"]) }
      end
    end

    # GET /products/get with filter=all and sku_seller_list=[seller_sku] (whole-word match). One request.
    # => Array<String> item ids.
    # https://open.lazada.com/apps/doc/api?path=/products/get
    def find_by_seller_sku(seller_sku)
      raise ArgumentError, "seller_sku is empty" if seller_sku.to_s.empty?

      response = session.get(Endpoints::PRODUCTS, { filter: "all", sku_seller_list: [seller_sku.to_s],
                                                    limit: PAGE_SIZE_MAX })
      products = response.data.is_a?(Hash) ? Array(response.data["products"]) : []
      products.grep(Hash).map { |product| product["item_id"].to_s }
    end

    # POST /product/deactivate with apiRequestBody = {"Request":{"Product":{"ItemId":id}}}: one product per call.
    # Sets absolute state, so it is idempotent.
    # https://open.lazada.com/apps/doc/api?path=/product/deactivate
    def unlist(product_ids)
      id = ids!(product_ids, "product_ids", UNLIST_BATCH_MAX).first
      session.post(Endpoints::PRODUCT_DEACTIVATE, { apiRequestBody: Resources.product_request({ "ItemId" => id.to_s }) },
                   idempotent: true)
    end

    # POST /product/global/update/status with type=single and status=upShelf: one product per call.
    # CROSS-BORDER SELLERS ONLY: Lazada documents no relist endpoint for local sellers. A local seller reactivates
    # SKUs with activate_skus. country is the configured endpoint's country (PH for :ph). Per-product failures
    # (update_ic_product_fail_result_list) are in #item_errors. Idempotent.
    # https://open.lazada.com/apps/doc/api?path=/product/global/update/status
    def relist(product_ids)
      id = ids!(product_ids, "product_ids", RELIST_BATCH_MAX).first
      body = { type: "single", country: session.connection.endpoint.to_s.upcase, product_id: id, status: "upShelf" }
      session.post(Endpoints::PRODUCT_STATUS, body, idempotent: true)
    end

    # Extension. POST /product/update with every given SKU's Status set to "active": how a local seller reactivates
    # SKUs (the update guide: Status is one of 'active', 'inactive' or 'deleted'). Lazada requires SkuId, so the
    # SKU ids are explicit; read them from products.get (skus[].SkuId). Idempotent.
    # https://open.lazada.com/apps/doc/doc?nodeId=30715&docId=121228
    def activate_skus(product_id, sku_ids)
      skus = ids!(sku_ids, "sku_ids", Float::INFINITY).map { |id| { "SkuId" => id.to_s, "Status" => "active" } }
      product = { "ItemId" => id!(product_id, "product_id").to_s, "Attributes" => {}, "Skus" => { "Sku" => skus } }
      session.post(Endpoints::PRODUCT_UPDATE, { payload: Resources.product_request(product) }, idempotent: true)
    end

    # Extension. GET /product/qc/alert/list (GetQCAlertProducts), offset-paged, stopped by a short page: the
    # products quality control flagged, with suggestionCategories and deactivationTime. Lazada documents no page
    # maximum; page_size defaults to 50.
    # https://open.lazada.com/apps/doc/api?path=/product/qc/alert/list
    def qc_alerts(page_size: nil, cursor: nil, **params)
      size = page_size.nil? ? QC_ALERTS_PAGE_SIZE : Integer(page_size)
      raise ArgumentError, "page_size must be positive, got #{size}" unless size.positive?

      Pager.new(cursor:) do |next_offset|
        start = offset(next_offset)
        response = session.get(Endpoints::QC_ALERTS, params.merge(offset: start, limit: size))
        offset_page(response, response.data.is_a?(Array) ? response.data : [], start, size)
      end
    end
  end
end
