# frozen_string_literal: true

# Conformance tests walk every adapter sample in one test, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "helper"

module Conformance
  class PagerTest < Minitest::Test
    include Support

    def build(pager_spec, *responses, **)
      client, transport = client_with(*responses)
      [pager_spec[:call].call(client, adapter.build_shop(client), **), transport]
    end

    def items_of(response, pager_spec)
      client, = client_with(response)
      pager_spec[:call].call(client, adapter.build_shop(client)).first_page.items
    end

    def test_three_pages_yield_every_item_in_order
      adapter.pagers.each do |spec|
        expected = spec[:pages].flat_map { |page| items_of(page, spec) }
        pager, transport = build(spec, *spec[:pages])

        assert_instance_of gem_module::Pager, pager
        assert_kind_of Enumerable, pager
        assert_equal expected, pager.to_a, spec[:name]
        assert_equal 3, transport.requests.size, spec[:name]
        refute_empty expected
      end
    end

    def test_lazy_first_makes_one_request
      adapter.pagers.each do |spec|
        pager, transport = build(spec, *spec[:pages])
        pager.lazy.first(1)

        assert_equal 1, transport.requests.size, spec[:name]
      end
    end

    def test_each_page_yields_pages_and_enumerators_without_blocks
      adapter.pagers.each do |spec|
        pager, = build(spec, *spec[:pages])

        assert_kind_of Enumerator, pager.each
        assert_kind_of Enumerator, pager.each_page
        pages = pager.each_page.to_a

        assert_equal 3, pages.size
        pages.each { |page| assert_instance_of gem_module::Page, page }
        pages[0..1].each { |page| assert_kind_of String, page.next_cursor }
        assert_nil pages.last.next_cursor
        pages.each { |page| assert_instance_of gem_module::Response, page.response }
      end
    end

    def test_first_page_next_cursor_resumes_the_walk
      adapter.pagers.reject { |spec| spec[:resumable] == false }.each do |spec|
        full, full_transport = build(spec, *spec[:pages])
        full.to_a
        first, = build(spec, spec[:pages][0])
        cursor = first.first_page.next_cursor
        resumed, resumed_transport = build(spec, spec[:pages][1], cursor:)
        resumed.first_page

        assert_equal adapter.request_identity(full_transport.requests[1]),
                     adapter.request_identity(resumed_transport.requests[0]), spec[:name]
      end
    end

    def test_an_empty_and_a_missing_final_token_both_stop
      adapter.pagers.each do |spec|
        assert_equal 2, spec[:final_variants].size
        spec[:final_variants].each do |final|
          pager, transport = build(spec, spec[:pages][0], final)
          pager.to_a

          assert_equal 2, transport.requests.size, spec[:name]
        end
      end
    end

    def test_page_size_above_the_maximum_raises
      adapter.pagers.select { |spec| spec[:max_page_size] }.each do |spec|
        client, transport = client_with
        assert_raises(ArgumentError, spec[:name]) do
          spec[:call].call(client, adapter.build_shop(client),
                           spec[:page_size_key] => spec[:max_page_size] + 1).first_page
        end
        assert_empty transport.requests
      end
    end

    def test_page_size_defaults_to_the_platform_maximum
      adapter.pagers.select { |spec| spec[:max_page_size] }.each do |spec|
        pager, transport = build(spec, spec[:pages][2])
        pager.first_page
        request = transport.requests.first
        sent = request.query[spec[:page_size_key].to_s] || (request.body && request.json[spec[:page_size_key].to_s])

        assert_equal spec[:max_page_size].to_s, sent.to_s, spec[:name]
      end
    end

    def test_hard_caps_raise_pagination_limit_error
      capped = adapter.pagers.select { |spec| spec[:cap] }
      skip "this platform documents no pagination hard cap" if capped.empty?

      capped.each do |spec|
        pager, = build(spec, *spec[:cap][:responses])

        assert_raises(gem_module::PaginationLimitError) { pager.to_a }
      end
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
