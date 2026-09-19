# frozen_string_literal: true

module LazadaRbApi
  class Prices < Resources::Base
    SKUS_MAX = 50

    # POST /product/price_quantity/update. skus: native Sku entries, e.g.
    # [{ "SkuId" => "234", "Price" => "1099.00", "SalePrice" => "900.00" }]; the gem sets each entry's ItemId.
    # Prices are decimal amounts in the shop's currency, not cents. At most 50 SKUs (20 recommended).
    # Sets absolute prices, so it is idempotent.
    # https://open.lazada.com/apps/doc/api?path=/product/price_quantity/update
    def update(product_id, skus)
      session.post(Endpoints::PRICE_QUANTITY, Resources.price_quantity(id!(product_id, "product_id"), batch!(skus, "skus", SKUS_MAX)),
                   idempotent: true)
    end
  end
end
