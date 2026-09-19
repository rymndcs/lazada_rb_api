# frozen_string_literal: true

module LazadaRbApi
  class Brands < Resources::Base
    PAGE_SIZE_MAX = 200

    # GET /category/brands/query (GetBrandByPages), offset-paged with startRow / pageSize and stopped by
    # total_record. Lazada's brand list is per REGION, not per category or shop, so category_id raises
    # ArgumentError. No authorization required. "The list of brands might change during paging."
    # https://open.lazada.com/apps/doc/api?path=/category/brands/query
    def list(category_id: nil, page_size: nil, cursor: nil, **params)
      raise ArgumentError, "Lazada brands are per region, not per category: drop category_id" unless category_id.nil?

      size = page_size!(page_size, PAGE_SIZE_MAX)
      Pager.new(cursor:) do |start|
        start = offset(start)
        response = session.get(Endpoints::BRANDS, params.merge(startRow: start, pageSize: size), public: true)
        data = response.data.is_a?(Hash) ? response.data : {}
        offset_page(response, data["module"], start, size, data["total_record"])
      end
    end
  end
end
