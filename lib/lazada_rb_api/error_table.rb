# frozen_string_literal: true

module LazadaRbApi
  # Classifies Lazada's `code` / `message` pair (and `detail[]`) into an ApiError subclass.
  #
  # Built from the error tables of every endpoint this gem calls (https://open.lazada.com/apps/doc/api?path=<path>,
  # pulled 2026-09-20) and the FAQ's rate-limit and seller-state codes (doc 239755). test/fixtures/error_list.json holds
  # every documented pair. Lazada overloads a few codes: `6` is an internal error on product calls but "Invalid status
  # filter" on /orders/get, and `500` / `501` / `503` are overview codes that wrap business failures in `detail[]`, so
  # the MESSAGE and DETAIL rules come first. A code this table does not name raises plain ApiError: the gem never
  # guesses a subclass.
  module ErrorTable
    OVERVIEW_CODES = %w[500 501 503 E500 E501].freeze

    # [code or nil, message pattern, class name]. The first matching rule wins.
    MESSAGE_RULES = [
      [nil, /SELLER_NOT_PERMITTED/, :PermissionError],
      ["MissingParameter", /"sign"|“sign”|\bsign\b/, :SignatureError],
      ["6", /Invalid status filter/i, :RequestError]
    ].freeze

    CODES = {
      SignatureError: %w[IncompleteSignature],
      AuthenticationError: %w[IllegalAccessToken IllegalRefreshToken InvalidCode],
      PermissionError: %w[
        InsufficientPermission AUTH_TYPE_UNSUPPORTED SellerNotActive SellerNotVerified ONLY_CB_SELLER_SUPPORTED
        EDIT_ITEM_NOT_BELONG_SELLER
      ],
      RateLimitError: %w[901 4154 ApiCallLimit AppApiCallLimit E1002 SellerCallLimit HOT_KEY_BLOCK_EXCEPTION],
      ConcurrencyError: %w[4147],
      ServerError: %w[
        6 E006 E0006 1000 300 502 506 513 4135 4159 ServiceTimeout SYS_ERROR SELLER_SERVICE_FAIL
        THIRD_SERVICE_ERROR IC_EXCEPTION
      ] + OVERVIEW_CODES,
      RequestError: %w[
        1 5 14 17 19 30 36 70 74 75 204 1001 4132 4171 4193 4216 E0001 E305 MissingParameter
      ],
      BusinessError: %w[
        16 57 200 201 202 205 206 207 208 209 302 303 512 701 4104 4105 4106 4107 4108 4109 4110 4111 4112 4113
        4114 4115 4116 4117 4118 4119 4120 4121 4122 4123 4124 4125 4126 4127 4128 4129 4130 4131 4133 4134 4136
        4137 4138 4139 4140 4141 4142 4143 4144 4145 4146 4148 4149 4150 4151 4152 4153 4155 4156 4157 4158 4160
        4161 4162 4163 4164 4165 4166 4167 4168 4169 4170 4218 4221 4225 4227 4228 10002 10006 E0002 E0003 E0004
      ]
    }.each_value(&:freeze).freeze

    BY_CODE = CODES.flat_map { |klass, codes| codes.map { |code| [code, klass] } }.to_h.freeze

    module_function

    # => the ApiError subclass for this error; ApiError itself when the code is not documented.
    # An overview code (500 / 501 / 503) that carries per-SKU reasons in detail[] is a business rejection, not a
    # server failure: "check the detail field in the API response to understand the SKU where the error occurred".
    def classify(code, message, detail = [])
      code = code.to_s
      rule = message_rule(code, message.to_s)
      return LazadaRbApi.const_get(rule) if rule
      return BusinessError if OVERVIEW_CODES.include?(code) && Array(detail).any?

      name = BY_CODE[code]
      name ? LazadaRbApi.const_get(name) : ApiError
    end

    def message_rule(code, message)
      MESSAGE_RULES.find { |rule_code, pattern, _| [nil, code].include?(rule_code) && message.match?(pattern) }&.last
    end

    # An HTTP-level failure with no Lazada error body.
    def classify_status(status)
      return RateLimitError if status == 429
      return ServerError if status >= 500

      ApiError
    end
  end
  private_constant :ErrorTable
end
