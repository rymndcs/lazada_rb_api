# frozen_string_literal: true

module LazadaRbApi
  class Stock < Resources::Base
    SKUS_MAX = 50

    # GET /product/item/get: the stock is in skus[].quantity and skus[].Available. Lazada has no separate stock read.
    # https://open.lazada.com/apps/doc/api?path=/product/item/get
    def get(product_id, **params)
      session.get(Endpoints::PRODUCT_ITEM, { item_id: id!(product_id, "product_id") }.merge(params))
    end

    # POST /product/price_quantity/update. skus: native Sku entries, e.g. [{ "SkuId" => "234", "Quantity" => "20" }]
    # or with MultiWarehouseInventories; the gem sets each entry's ItemId. At most 50 SKUs (20 recommended).
    # Sets absolute stock, so it is idempotent.
    # https://open.lazada.com/apps/doc/api?path=/product/price_quantity/update
    def update(product_id, skus)
      session.post(Endpoints::PRICE_QUANTITY, Resources.price_quantity(id!(product_id, "product_id"), batch!(skus, "skus", SKUS_MAX)),
                   idempotent: true)
    end
  end

end
