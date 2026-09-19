# frozen_string_literal: true

module LazadaRbApi
  class Orders < Resources::Base
    PAGE_SIZE_MAX = 100

    # GET /orders/get, offset-paged (offset / limit), stopped by countTotal. Lazada requires created_after or
    # update_after (ISO 8601): pass them in params with any other filter (status, sort_by, sort_direction).
    # Read-only.
    # https://open.lazada.com/apps/doc/api?path=/orders/get
    def list(page_size: nil, cursor: nil, **params)
      size = page_size!(page_size, PAGE_SIZE_MAX)
      Pager.new(cursor:) do |next_offset|
        start = offset(next_offset)
        response = session.get(Endpoints::ORDERS, params.merge(limit: size, offset: start))
        data = response.data.is_a?(Hash) ? response.data : {}
        offset_page(response, data["orders"], start, size, data["countTotal"])
      end
    end

    # GET /order/get with order_id. Read-only.
    # https://open.lazada.com/apps/doc/api?path=/order/get
    def get(order_id, **params)
      session.get(Endpoints::ORDER, { order_id: id!(order_id, "order_id") }.merge(params))
    end

    # Extension. GET /order/items/get: Lazada keeps order lines apart from the order header. Read-only.
    # https://open.lazada.com/apps/doc/api?path=/order/items/get
    def items(order_id)
      session.get(Endpoints::ORDER_ITEMS, { order_id: id!(order_id, "order_id") })
    end
  end
end
