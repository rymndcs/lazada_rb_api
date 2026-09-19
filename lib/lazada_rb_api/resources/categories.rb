# frozen_string_literal: true

module LazadaRbApi
  class Categories < Resources::Base
    # GET /category/tree/get: the whole nested tree (not paged). No authorization required, so the token is not
    # sent. Native params: language_code.
    # https://open.lazada.com/apps/doc/api?path=/category/tree/get
    def list(**params)
      session.get(Endpoints::CATEGORY_TREE, params, public: true)
    end

    # GET /category/attributes/get with primary_category_id = category_id. No authorization required.
    # https://open.lazada.com/apps/doc/api?path=/category/attributes/get
    def attributes(category_id, **params)
      query = { primary_category_id: id!(category_id, "category_id") }.merge(params)
      session.get(Endpoints::CATEGORY_ATTRIBUTES, query, public: true)
    end

    # GET /product/category/suggestion/get; title is sent as product_name. Lazada also requires image_url: pass it
    # in params. The payload is data.categorySuggestions[].
    # https://open.lazada.com/apps/doc/api?path=/product/category/suggestion/get
    def recommend(title:, **params)
      session.get(Endpoints::CATEGORY_SUGGESTION, { product_name: title.to_s }.merge(params))
    end
  end
end
