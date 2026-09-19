# frozen_string_literal: true

module LazadaRbApi
  # Keeps secrets out of `pp` output: pretty_print falls back to the redacted #inspect.
  module Redaction
    REDACTED = "[REDACTED]"

    def pretty_print(printer)
      printer.text(inspect)
    end
  end
  private_constant :Redaction
end
