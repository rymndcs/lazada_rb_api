# Changelog

All notable changes to this gem are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and the gem follows Semantic Versioning. Versions stay
`0.x` until the opt-in live tests have recorded real Lazada responses over the documentation fixtures.

## [Unreleased]

### Added

- The first release surface of the shared interface (`CONTRACT.md`, `CONTRACT_VERSION = "2"`): `Client`, `Auth`,
  `Shop`, categories, brands, media, products (including `relist`), stock, prices, read-only orders, webhooks,
  `request`, `Response`, `Pager`, the error tree, `RetryPolicy` and `Transport::NetHttp` (RAC-276).
- `products.relist` calls `/product/global/update/status` (`upShelf`), which Lazada documents for cross-border
  sellers only: Lazada has no relist endpoint for local sellers (RAC-276).
- Lazada extensions: `products.activate_skus` (local-seller SKU reactivation through `/product/update`),
  `products.qc_alerts`, `orders.items` and `shop.item_limit` (GetSellerItemLimit) (RAC-276).
- Every Lazada host as configuration: the `ENDPOINTS` table (`:ph` default, `:my`, `:sg`, `:th`, `:vn`, `:id`),
  each with its API, consent and token hosts, plus `base_url:` / `auth_base_url:` / `token_base_url:` for any other
  host. `token_base_url:` is a declared constructor keyword with a reader, as contract v2 allows (RAC-276).
- The shared files copied byte-for-byte from `shopee_rb_api` and pinned by `test/conformance/MANIFEST` (RAC-276).
- Opt-in live tests (`rake test:live`) that can record redacted responses into `test/fixtures/`. Order responses are
  never recorded, and customer personal data is redacted from every other response (RAC-276).
