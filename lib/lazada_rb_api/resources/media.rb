# frozen_string_literal: true

module LazadaRbApi
  class Media < Resources::Base
    # POST /image/upload, multipart, one image per call (the `image` file part, which is not signed). JPG or PNG;
    # the API page says at most 1 MB, the Image Upload guide 3 MB. params are extra form fields. The payload is
    # data.image {url, hash_code}. Not idempotent.
    # https://open.lazada.com/apps/doc/api?path=/image/upload
    def upload_image(io, filename: nil, **params)
      raise ArgumentError, "io must respond to #read" unless io.respond_to?(:read)

      filename ||= io.respond_to?(:path) && io.path ? File.basename(io.path) : "image"
      session.upload(Endpoints::IMAGE_UPLOAD, params, { name: "image", filename:, content: io.read })
    end
  end
end
