# frozen_string_literal: true

module LazadaRbApi
  # A lazy walk over a paged endpoint. Pages are fetched only as items are consumed:
  # `pager.lazy.first(10)` makes as few requests as it can. Each page is one request.
  class Pager
    include Enumerable

    # fetch: called with the cursor (nil for the first page) and returns a Page.
    def initialize(cursor: nil, &fetch)
      raise ArgumentError, "a fetch block is required" unless fetch

      @cursor = cursor
      @fetch = fetch
    end

    def each(&block)
      return enum_for(:each) unless block

      each_page { |page| page.items.each(&block) }
      self
    end

    def each_page
      return enum_for(:each_page) unless block_given?

      cursor = @cursor
      loop do
        page = @fetch.call(cursor)
        yield page
        break if page.next_cursor.nil?

        cursor = page.next_cursor
      end
      self
    end

    def first_page
      @fetch.call(@cursor)
    end
  end
end
