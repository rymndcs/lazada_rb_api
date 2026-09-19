# frozen_string_literal: true

# A parsed event is checked field by field.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

# Lazada pushes (https://open.lazada.com/apps/doc/doc?nodeId=29524&docId=120168 and the Webhook APIs pages).
class WebhookTest < Minitest::Test
  include UnitHelper

  def parse(body)
    LazadaRbApi::Webhook.parse(body)
  end

  def test_token_expiry_alert_reads_the_seller_id_inside_data
    event = parse(A::EXPIRY_PUSH)

    assert_equal :authorization_expiring, event.type
    assert_equal "1000165972", event.shop_id
    assert_equal 1_627_542_238, event.data["auth_expiry_time"]
  end

  def test_other_message_types_keep_their_code
    event = parse('{"seller_id":"100053528","message_type":13,"data":{"status":"close"},"timestamp":1627038397,' \
                  '"site":"lazada_sg"}')

    assert_equal :other, event.type
    assert_equal "13", event.code
    assert_equal "100053528", event.shop_id
    assert_equal Time.at(1_627_038_397).utc, event.occurred_at
  end

  def test_a_broadcast_has_no_shop_and_millisecond_timestamps_are_read
    event = parse('{"message_type":12,"data":{"status":"finish"},"timestamp":1627203600000,"site":"lazada_sg"}')

    assert_nil event.shop_id
    assert_equal Time.at(1_627_203_600).utc, event.occurred_at
  end

  def test_invalid_bodies
    assert_raises(ArgumentError) { parse("not json") }
    assert_raises(ArgumentError) { parse("[1]") }
  end

  def test_client_verify_webhook_ignores_the_url
    client, = client_with
    vector = A.webhook_vectors.first
    event = client.verify_webhook(raw_body: vector[:raw_body], signature: vector[:signature],
                                  url: "https://anything.test")

    assert_equal :authorization_expiring, event.type
  end
end
# rubocop:enable Minitest/MultipleAssertions
