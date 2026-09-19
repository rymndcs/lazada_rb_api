# frozen_string_literal: true

module LazadaRbApi
  # Lazada request signing (https://open.lazada.com/apps/doc/doc?nodeId=10400&docId=108068): upper-case hex
  # HMAC-SHA256, keyed with the app secret, over the API path followed by every parameter (system and business, but
  # not `sign` and not file parts) sorted by name in ASCII byte order and concatenated as name + value, with no
  # separators and no URL encoding. The gem never sends an empty parameter, so empty values never reach the base
  # string (the official samples disagree on whether to sign them).
  #
  # Push verification (https://open.lazada.com/apps/doc/doc?nodeId=29524&docId=120168): lower-case hex
  # HMAC-SHA256, keyed with the app secret, over app_key + the raw body.
  module Signer
    module_function

    # params: { String => String }. => the UTF-8 (binary) base string.
    def base_string(path, params)
      pairs = params.filter_map { |key, value| [key.to_s.b, value.to_s.b] unless value.nil? || value.to_s.empty? }
      pairs.sort_by(&:first).each_with_object(path.to_s.b.dup) { |(key, value), out| out << key << value }
    end

    def sign(secret, base_string)
      OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, base_string).upcase
    end

    def push_base_string(app_key, raw_body)
      "#{app_key.to_s.b}#{raw_body.to_s.b}".b
    end

    def push_sign(secret, base_string)
      OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, base_string)
    end
  end
  private_constant :Signer
end
