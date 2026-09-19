# frozen_string_literal: true

module LazadaRbApi
  # Every non-paged call returns a Response. `data` is the platform payload verbatim with the envelope removed;
  # `raw` is the parsed body exactly as received. Both are deeply frozen.
  Response = Data.define(:data, :request_id, :warnings, :item_errors, :http_status, :endpoint, :raw)

  # Turns Lazada's envelopes into a Response, or raises the classified ApiError.
  #
  # Lazada has one common envelope and a few odd ones (https://open.lazada.com/apps/doc/doc?nodeId=10397&docId=108138
  # and the API pages):
  # - standard: {"code":"0","data":…,"request_id":…}; an error has a code other than "0", a message, a type
  #   (SYSTEM / ISV / ISP) and sometimes detail[];
  # - GetPreQcRules puts its payload under `values`, and the content score under `result`;
  # - GetBrandByPages and updateProductStatus add success / error_code / error_msg;
  # - GetSellerItemLimit adds success / errorCodes[] / errorMsgs[];
  # - the token API returns the whole document at the top level, with no `data`.
  module Envelope
    ENVELOPE_KEYS = %w[code type message request_id detail success error_code error_msg errorCodes errorMsgs].freeze
    PAYLOAD_KEYS = %w[data values result].freeze
    # "API level QPS limiting flow, please retry in the next second" (every /901 row in the error tables).
    NEXT_SECOND = { "901" => 1.0 }.freeze

    module_function

    # What an error needs besides the body: where the call went, whether it was idempotent, the response headers
    # and the time it was stamped.
    Call = Data.define(:endpoint, :idempotent, :headers, :now)

    def build(result, endpoint:, idempotent:, now:)
      status = result.fetch(:status).to_i
      call = Call.new(endpoint:, idempotent:, headers: result[:headers] || {}, now:)
      parsed = parse(result[:body])
      raise http_error(status, call) if parsed.nil?

      response = to_response(parsed, status, endpoint)
      failure = failure(parsed)
      raise api_error(failure, parsed, response, call) if failure
      raise http_error(status, call, response) if status >= 400

      response
    end

    def parse(body)
      parsed = JSON.parse(body.to_s)
      parsed.is_a?(Hash) ? parsed : nil
    rescue JSON::ParserError
      nil
    end

    # => [code, message] when the body reports an error, else nil. `success` is sent as a boolean or as the
    # string "false"; a response with success true may still carry a stale error_code, which is ignored.
    def failure(parsed)
      code = parsed["code"]
      return [code.to_s, parsed["message"].to_s] unless code.nil? || code.to_s == "0"
      return nil unless [false, "false"].include?(parsed["success"])

      [(parsed["error_code"] || Array(parsed["errorCodes"]).first).to_s,
       (parsed["error_msg"] || Array(parsed["errorMsgs"]).first).to_s]
    end

    def to_response(parsed, status, endpoint)
      data = payload(parsed)
      Response.new(data: deep_freeze(data), request_id: parsed["request_id"]&.to_s, warnings: [].freeze,
                   item_errors: item_errors(data).freeze, http_status: status, endpoint:, raw: deep_freeze(parsed))
    end

    # A null or absent payload is an empty Hash.
    def payload(parsed)
      key = PAYLOAD_KEYS.find { |k| parsed.key?(k) }
      return parsed.except(*ENVELOPE_KEYS) unless key

      value = parsed[key]
      value.nil? ? {} : value
    end

    # updateProductStatus reports per-product failures inside a success:
    # data.update_ic_product_fail_result_list[] with update_result false.
    def item_errors(data)
      return [] unless data.is_a?(Hash) && data["update_ic_product_fail_result_list"].is_a?(Array)

      data["update_ic_product_fail_result_list"].grep(Hash).reject { |entry| truthy?(entry["update_result"]) }
                                                .map do |entry|
        ItemError.new(id: entry["product_id"].to_s, code: "", message: entry["update_msg"].to_s,
                      raw: deep_freeze(entry))
      end
    end

    def truthy?(value)
      [true, "true"].include?(value)
    end

    def api_error(failure, parsed, response, call)
      code, message = failure
      detail = parsed["detail"].is_a?(Array) ? parsed["detail"] : []
      klass = ErrorTable.classify(code, message, detail)
      klass.new(message.empty? ? code : message, code:, request_id: response.request_id,
                                                 http_status: response.http_status, endpoint: call.endpoint,
                                                 detail: deep_freeze(detail), response:, idempotent: call.idempotent,
                                                 retry_after: retry_after(call, code))
    end

    def http_error(status, call, response = nil)
      klass = ErrorTable.classify_status(status)
      klass.new("HTTP #{status}", code: status.to_s, request_id: response&.request_id, http_status: status,
                                  endpoint: call.endpoint, detail: [], response:, idempotent: call.idempotent,
                                  retry_after: retry_after(call))
    end

    def retry_after(call, code = nil)
      header = call.headers.find { |k, _| k.to_s.casecmp?("retry-after") }&.last
      parse_retry_after(Array(header).first, call.now) || NEXT_SECOND[code]
    end

    def parse_retry_after(value, now)
      return nil if value.nil? || value.to_s.strip.empty?
      return Float(value) if value.to_s.match?(/\A\s*\d+(\.\d+)?\s*\z/)

      [Time.httpdate(value.to_s) - now, 0.0].max
    rescue ArgumentError
      nil
    end

    def deep_freeze(value)
      case value
      when Hash then value.each_value { |v| deep_freeze(v) }.freeze
      when Array then value.each { |v| deep_freeze(v) }.freeze
      when String then value.freeze
      else value
      end
    end
  end
  private_constant :Envelope
end
