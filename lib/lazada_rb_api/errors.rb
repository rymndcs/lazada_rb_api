# frozen_string_literal: true

module LazadaRbApi
  class Error < StandardError
    def retryable?
      false
    end
  end

  # A bad keyword, an unknown endpoint, a malformed host URL.
  class ConfigurationError < Error; end

  # No platform response was read: timeout, connection reset, TLS failure.
  class TransportError < Error
    def initialize(message = nil, idempotent: false)
      super(message)
      @idempotent = idempotent
    end

    # True only when the request was idempotent: nobody knows whether a timed-out write landed.
    def retryable?
      @idempotent
    end
  end

  # A platform hard cap stopped a Pager, so the walk would otherwise be silently truncated.
  class PaginationLimitError < Error; end

  # An inbound webhook (Lazada push) failed verification.
  class WebhookSignatureError < Error; end

  # The platform answered with an error.
  class ApiError < Error
    attr_reader :code, :request_id, :http_status, :endpoint, :detail, :response, :retry_after

    def initialize(message = nil, code: "", request_id: nil, http_status: nil, endpoint: nil, detail: [],
                   response: nil, retry_after: nil, idempotent: false)
      super(message)
      @code = code.to_s
      @request_id = request_id
      @http_status = http_status
      @endpoint = endpoint
      @detail = detail.freeze
      @response = response
      @retry_after = retry_after
      @idempotent = idempotent
    end
  end

  # This shop's token is invalid or expired, or the token and shop do not match: refresh or re-consent.
  class AuthenticationError < ApiError; end
  # The app key or secret is invalid, or the app is deleted or restricted: every shop is down.
  class AppCredentialsError < ApiError; end
  # Scope or API permission, IP allow-list, seller or shop inactive or banned, KYC.
  class PermissionError < ApiError; end
  # The platform rejected the signature or timestamp: a gem bug or clock skew.
  class SignatureError < ApiError; end
  # A malformed request: missing parameter, bad path, method, version or content type.
  class RequestError < ApiError; end
  # A documented business rejection: validation, content, entitlement, not found.
  class BusinessError < ApiError; end

  # Throttled; the call was not executed.
  class RateLimitError < ApiError
    def retryable?
      true
    end
  end

  # The daily app quota is exhausted; the call was not executed. Retry after #retry_after.
  class QuotaExceededError < ApiError
    def retryable?
      true
    end
  end

  # A concurrent edit was refused; the call was not executed.
  class ConcurrencyError < ApiError
    def retryable?
      true
    end
  end

  # The platform failed internally. For a write the outcome is UNKNOWN, so only idempotent calls are retryable.
  class ServerError < ApiError
    def retryable?
      @idempotent
    end
  end
end
