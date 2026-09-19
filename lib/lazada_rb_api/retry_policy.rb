# frozen_string_literal: true

module LazadaRbApi
  # Opt-in retries. The default, RetryPolicy.none, never retries. An opt-in policy retries only errors whose
  # #retryable? is true, waiting max(retry_after, min(base * 2**n + rand(jitter), cap)) seconds: TikTok Shop's
  # published protocol, the strictest of the three platforms. Each attempt is re-stamped and re-signed.
  class RetryPolicy
    attr_reader :max_retries

    def self.none
      new(max_retries: 0)
    end

    def initialize(max_retries: 5, base: 1.0, cap: 60.0, jitter: 0.5, sleeper: ->(seconds) { sleep(seconds) })
      raise ArgumentError, "max_retries must be >= 0" if max_retries.to_i.negative?

      @max_retries = max_retries.to_i
      @base = base.to_f
      @cap = cap.to_f
      @jitter = jitter.to_f
      @sleeper = sleeper
      freeze
    end

    # Seconds to wait before retry number `attempt` (0-based) after `error`.
    def delay_for(error, attempt)
      backoff = [(@base * (2**attempt)) + (@jitter.positive? ? Random.rand * @jitter : 0.0), @cap].min
      [error.respond_to?(:retry_after) ? error.retry_after.to_f : 0.0, backoff].max
    end

    # Runs the block, retrying it on retryable errors. The block must re-sign its request on every call.
    def run
      attempt = 0
      begin
        yield
      rescue Error => e
        raise unless e.retryable? && attempt < @max_retries

        @sleeper.call(delay_for(e, attempt))
        attempt += 1
        retry
      end
    end
  end
end
