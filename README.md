# lazada_rb_api

A Ruby client for the [Lazada Open Platform](https://open.lazada.com/apps/doc/doc?nodeId=10400&docId=108068): signed
requests, seller authorization and tokens, catalogue, products, stock, prices, read-only orders, and push (webhook)
verification. No runtime dependencies: `net/http`, `openssl` and `json` from the standard library.

It is a library. It implements Lazada faithfully and configurably and leaves every deployment decision to you: which
country host, when to refresh or ask a seller to re-consent, which limit endpoint to trust, and how to store tokens.

It is one of three sibling gems (`shopee_rb_api`, `lazada_rb_api`, `tiktok_shop_rb_api`) that share one interface,
written down in [CONTRACT.md](CONTRACT.md). Code written against one of them reads the same against the others.

Status: `0.x`. The response fixtures come from Lazada's documentation samples (mostly dated 2022); the version stays
below 1.0 until the opt-in live tests (see Testing) have recorded real responses over them.

## Installation

The gem is not published to RubyGems. Pin it by git tag:

```ruby
# Gemfile
gem "lazada_rb_api", git: "https://github.com/rymndcs/lazada_rb_api.git", tag: "v0.1.0"
```

Ruby 3.3 or newer.

## Configuration

One `Client` per Lazada app. There is no global configuration; the client is immutable and thread-safe.

```ruby
require "lazada_rb_api"

client = LazadaRbApi::Client.new(
  app_key: ENV.fetch("LAZADA_APP_KEY"),
  app_secret: ENV.fetch("LAZADA_APP_SECRET"),
  endpoint: :ph,                               # default; see the table below
  transport: LazadaRbApi::Transport::NetHttp.new(open_timeout: 5, read_timeout: 30),
  clock: -> { Time.now },
  logger: Rails.logger,                        # debug lines only; never a secret
  retry_policy: LazadaRbApi::RetryPolicy.none  # the default: the gem never retries on its own
)
```

Hosts are configuration, not code. `endpoint:` picks the country's API host from `LazadaRbApi::ENDPOINTS`, together
with the consent page host and the token API host, which every country shares:

| `endpoint:` | API host | Consent page host | Token API host |
|---|---|---|---|
| `:ph` (default) | `https://api.lazada.com.ph/rest` | `https://auth.lazada.com` | `https://auth.lazada.com/rest` |
| `:my` | `https://api.lazada.com.my/rest` | same | same |
| `:sg` | `https://api.lazada.sg/rest` | same | same |
| `:th` | `https://api.lazada.co.th/rest` | same | same |
| `:vn` | `https://api.lazada.vn/rest` | same | same |
| `:id` | `https://api.lazada.co.id/rest` | same | same |

A Lazada token belongs to one country and works only against that country's host ("Tokens are not interchangeable
across sites"), so build the client for the credential's country. For any other host (a proxy, a new country) pass a
URL:

```ruby
LazadaRbApi::Client.new(app_key: key, app_secret: secret, endpoint: :ph,
                        base_url: "https://lazada-egress.internal/rest",    # API host
                        auth_base_url: "https://auth.lazada.com",           # consent page host
                        token_base_url: "https://auth.lazada.com/rest")     # token API host
```

`token_base_url:` is a declared constructor keyword (contract v2, `EXTENSIONS["Client#token_base_url"]`);
`client.token_base_url` reads the token host in use.

Lazada has no sandbox host: testing uses a Testing-status app and test seller accounts against the production hosts.

## Authorization

The gem stores no tokens and never refreshes on its own. Lazada returns a new refresh token on every refresh and does
not document whether the old one survives, so persist both tokens of every `Grant` in one write before doing anything
else. Lazada's own documents disagree on token lifetimes (10 days / 50 days in the authorization guide, 30 days / 180
days for an Online app in the FAQ); the gem reports exactly what each response says.

```ruby
# 1. Send the seller to the consent page. redirect_uri must match the app's callback URL.
url = client.auth.authorize_url(redirect_uri: "https://app.example/lazada/callback", state: csrf_token)

# 2. Lazada redirects back with code (valid 30 minutes, single use). No locator: one code is one store.
grant = client.auth.exchange_code(code: params[:code])
grant.access_token; grant.refresh_token
grant.access_token_expires_at   # absolute UTC Time, from expires_in and the injected clock
grant.refresh_token_expires_at  # absolute UTC Time, from refresh_expires_in
grant.shop_ids                  # ["1001"]: country_user_info[].seller_id
grant.raw["country"]            # "ph": the country whose host this token works on

# 3. Refresh before the access token expires.
grant = client.auth.refresh(refresh_token: stored.refresh_token)

# The one store a token reaches.
client.authorized_shops(access_token: grant.access_token).each do |ref|
  ref.shop_id; ref.name; ref.region; ref.locator  # => {}
end
```

## Shop session (locator)

```ruby
shop = client.shop(access_token: stored.access_token)
shop.locator  # => {}; LazadaRbApi::Shop::LOCATOR_KEYS == []
```

One Lazada token is one store, and the host carries the country, so a Lazada shop needs no locator.

## Capabilities

Every method makes exactly one request (iterating a `Pager` makes one per page). Identity arguments (`product_id`,
`category_id`, `order_id`, `seller_sku`, `title`) accept a String or an Integer; everything else is Lazada's own
field names, passed through untouched. Non-paged methods return a `LazadaRbApi::Response`.

Product payloads are Lazada's native `Product` node; the gem wraps it as `{"Request":{"Product":…}}` and sends it as
the `payload` parameter. Hash and Array parameters are sent as JSON; empty parameters are never sent.

| Capability | Example | Lazada endpoint |
|---|---|---|
| Shop info | `shop.info.data["status"]` | [`/seller/get`](https://open.lazada.com/apps/doc/api?path=/seller/get) |
| Listing limits | `shop.limits(option: 1, option_set: [1, 2]).data["item_limit"]` | [`/product/seller/item/getPreQcRules`](https://open.lazada.com/apps/doc/api?path=/product/seller/item/getPreQcRules) |
| Category tree | `shop.categories.list(language_code: "en_US").data` | [`/category/tree/get`](https://open.lazada.com/apps/doc/api?path=/category/tree/get) |
| Category attributes | `shop.categories.attributes(10100687, language_code: "en_US").data` | [`/category/attributes/get`](https://open.lazada.com/apps/doc/api?path=/category/attributes/get) |
| Category suggestion | `shop.categories.recommend(title: "Bosch H4 bulb", image_url: lazada_image_url).data["categorySuggestions"]` | [`/product/category/suggestion/get`](https://open.lazada.com/apps/doc/api?path=/product/category/suggestion/get) |
| Brands (per region) | `shop.brands.list.each { \|b\| b["brand_id"] }` | [`/category/brands/query`](https://open.lazada.com/apps/doc/api?path=/category/brands/query) |
| Image upload | `shop.media.upload_image(File.open("bulb.jpg")).data["image"]["url"]` | [`/image/upload`](https://open.lazada.com/apps/doc/api?path=/image/upload) |
| Create product | `shop.products.create({ "PrimaryCategory" => "10100687", "disableAutoFillAttribute" => true, "Images" => { "Image" => [url] }, "Attributes" => { "name" => "...", "brand_id" => "30768" }, "Skus" => { "Sku" => [{ "SellerSku" => "OT405", "price" => "638.00", "quantity" => "100", "package_length" => "12", "package_width" => "8", "package_height" => "6", "package_weight" => "0.2" }] } }).data["item_id"]` | [`/product/create`](https://open.lazada.com/apps/doc/api?path=/product/create) |
| Get product | `shop.products.get(2374791958).data["status"]` | [`/product/item/get`](https://open.lazada.com/apps/doc/api?path=/product/item/get) |
| Update product (partial) | `shop.products.update(2374791958, { "Attributes" => {}, "Skus" => { "Sku" => [{ "SkuId" => sku_id, "price" => "599.00" }] } })` | [`/product/update`](https://open.lazada.com/apps/doc/api?path=/product/update) |
| List products | `shop.products.list(filter: "live", update_after: "2026-09-01T00:00:00+08:00").each { \|p\| p["item_id"] }` | [`/products/get`](https://open.lazada.com/apps/doc/api?path=/products/get) |
| Find by seller SKU | `shop.products.find_by_seller_sku("OT405") # => ["2374791958"]` | [`/products/get`](https://open.lazada.com/apps/doc/api?path=/products/get) with `sku_seller_list` |
| Unlist | `shop.products.unlist([2374791958])` (≤ `Products::UNLIST_BATCH_MAX` = 1) | [`/product/deactivate`](https://open.lazada.com/apps/doc/api?path=/product/deactivate) |
| Relist (cross-border sellers only) | `shop.products.relist([2374791958]).item_errors` (≤ `Products::RELIST_BATCH_MAX` = 1) | [`/product/global/update/status`](https://open.lazada.com/apps/doc/api?path=/product/global/update/status) with `status: upShelf` |
| Get stock | `shop.stock.get(2374791958).data["skus"].map { \|s\| s["quantity"] }` | [`/product/item/get`](https://open.lazada.com/apps/doc/api?path=/product/item/get) |
| Update stock | `shop.stock.update(2374791958, [{ "SkuId" => sku_id, "Quantity" => "100" }])` (≤ 50 SKUs) | [`/product/price_quantity/update`](https://open.lazada.com/apps/doc/api?path=/product/price_quantity/update) |
| Update prices | `shop.prices.update(2374791958, [{ "SkuId" => sku_id, "Price" => "638.00", "SalePrice" => "599.00" }])` (≤ 50 SKUs) | [`/product/price_quantity/update`](https://open.lazada.com/apps/doc/api?path=/product/price_quantity/update) |
| List orders (read-only) | `shop.orders.list(update_after: "2026-09-19T00:00:00+08:00").each { \|o\| o["order_id"] }` | [`/orders/get`](https://open.lazada.com/apps/doc/api?path=/orders/get) |
| Get order (read-only) | `shop.orders.get(491253082180001).data["statuses"]` | [`/order/get`](https://open.lazada.com/apps/doc/api?path=/order/get) |

**Lazada extensions** (declared in `LazadaRbApi::EXTENSIONS`; no sibling gem has them in this shape):

| Extension | Example | Lazada endpoint |
|---|---|---|
| Reactivate SKUs (local sellers) | `shop.products.activate_skus(2374791958, [sku_id_1, sku_id_2])` | [`/product/update`](https://open.lazada.com/apps/doc/doc?nodeId=30715&docId=121228) with each SKU's `Status` `"active"` |
| QC alerts | `shop.products.qc_alerts.each { \|a\| a["suggestionCategories"] }` | [`/product/qc/alert/list`](https://open.lazada.com/apps/doc/api?path=/product/qc/alert/list) |
| Order lines | `shop.orders.items(491253082180001).data` | [`/order/items/get`](https://open.lazada.com/apps/doc/api?path=/order/items/get) |
| Seller item limit | `shop.item_limit.data["itemLimit"]` | [`/product/seller/item/limit`](https://open.lazada.com/apps/doc/api?path=/product/seller/item/limit) |

Lazada facts worth knowing before you publish:

- **Relist.** Lazada has no relist endpoint for local sellers. `products.relist` calls `updateProductStatus`
  (`upShelf`), which Lazada documents for cross-border sellers only, with `country` set from the configured endpoint.
  A local seller reactivates SKUs with `products.activate_skus`; read the SKU ids from `products.get`
  (`skus[].SkuId`).
- **Limits.** `shop.limits` calls GetPreQcRules (`item_limit`, `item_count`, `restricted_cate_ids`, under `values`).
  `shop.item_limit` calls GetSellerItemLimit, which Lazada documents as cross-border only
  (`ONLY_CB_SELLER_SUPPORTED`, a `PermissionError`, for a local seller). Which one to trust is your choice.
- **Brands** are per region, not per shop or category: `brands.list` raises `ArgumentError` for `category_id:`.
  Per-shop brand eligibility shows up only as create errors (`4130`, `4156`, `4168`).
- The category tree, category attributes and brands need no authorization, so the gem does not send the token on them.
- `/product/update` needs `SkuId` on every SKU and an `Attributes` node (it may be empty). Seller SKU lookups by
  `seller_sku` on `/product/item/get` were removed in 2023; persist `item_id` and every `sku_id` from the create
  response.
- Numbers and booleans often arrive as strings, inconsistently (`"item_id": "2374791958"` next to `"SkuId":
  314525867`). The gem never coerces them.
- Prices are decimal amounts in the shop's currency, not cents. Package dimensions are cm and weight kg, two decimals.
- Concurrent edits of one item fail with `4147` (`ConcurrencyError`, retryable): serialize edits per item.
- `/product/price_quantity/update` takes at most 50 SKUs (Lazada recommends 20).

### Response

```ruby
res = shop.products.relist([3042450256])
res.data         # the payload with Lazada's envelope removed, frozen, never coerced
res.request_id   # Lazada's request_id
res.warnings     # [] (Lazada reports no degraded successes)
res.item_errors  # [#<data ItemError id="3042450256", code="", message="Product is not found in repository, ...">]
res.http_status; res.endpoint; res.raw
```

Lazada's payload sits under `data` on most endpoints, under `values` on GetPreQcRules, and at the top level on the
token endpoints; GetBrandByPages, updateProductStatus and GetSellerItemLimit add `success` flags. `data` hides that
difference; `raw` keeps the body as received.

## Pagination

```ruby
pager = shop.products.list(filter: "live", update_after: "2026-09-01T00:00:00+08:00", page_size: 50)
pager.each { |product| ... }            # every product, fetching pages lazily
pager.lazy.first(10)                    # only as many requests as needed
pager.each_page { |page| page.items; page.next_cursor; page.total }
page = pager.first_page
shop.products.list(filter: "live", update_after: "2026-09-01T00:00:00+08:00", cursor: page.next_cursor)  # resume later
```

`next_cursor` is an opaque String: store it, pass it back, never parse it. `page_size:` defaults to Lazada's maximum
(products 50, orders 100, brands 200) and raises `ArgumentError` above it. Lazada documents no maximum for QC alerts;
`qc_alerts` defaults to 50. Lazada caps `/products/get` at offset 10,000: a walk that would pass it raises
`PaginationLimitError`. Narrow the `update_after` / `update_before` window yourself; the gem never splits windows.

## Errors and retries

Every failure raises a subclass of `LazadaRbApi::Error`; see [CONTRACT.md §8](CONTRACT.md) for the tree. Lazada
signals errors in the body (a `code` other than `"0"`, or `success: false`), whatever the HTTP status. The class comes
from Lazada's `code`, and from the `message` or `detail[]` where Lazada overloads a code: `500`, `501` and `503` are
overview codes, a `BusinessError` when `detail[]` names the failing SKUs and a `ServerError` when it does not. A code
the table does not know raises plain `ApiError`.

```ruby
begin
  shop.products.update(2374791958, payload)
rescue LazadaRbApi::AuthenticationError
  # refresh (once, persisting both tokens) or ask the seller to re-authorize
rescue LazadaRbApi::RateLimitError => e
  e.retry_after  # 1.0 for 901 ("retry in the next second"), or the Retry-After header
rescue LazadaRbApi::ApiError => e
  e.code; e.message; e.detail; e.request_id; e.retryable?
end
```

Retries are off by default. Opt in with a policy; it retries only `retryable?` errors (rate limits, concurrent edits,
and server or network errors on idempotent calls) and re-signs every attempt:

```ruby
LazadaRbApi::Client.new(..., retry_policy: LazadaRbApi::RetryPolicy.new(max_retries: 5))
```

Lazada has no idempotency key, so `products.create`, `products.update` and `media.upload_image` are never retried:
after a timeout, look the SellerSku up with `find_by_seller_sku` before trying again.

## Webhooks

Lazada signs each push with `HMAC-SHA256(app_secret, app_key + raw_body)` in the `Authorization` header.

```ruby
event = client.verify_webhook(raw_body: request.raw_post, signature: request.headers["Authorization"])
event.type         # :authorization_expiring (message_type 8, 48 hours ahead) | :product_status (1, QC) | :other
event.code         # "8", "1", "0" (trade order), "13" (seller status), ...
event.shop_id; event.occurred_at; event.data
```

- Verify the raw body as received; never re-serialize parsed JSON.
- Reply **HTTP 200 within 500 ms**. Otherwise Lazada retries every 30 minutes, up to 12 times.
- The callback URL must serve a CA-issued **OV or EV** certificate; Lazada refuses DV and self-signed ones.
- Delivery is at least once: consume idempotently.
- `LazadaRbApi::Webhook.verify(...)` and `.parse(raw_body)` are the pure functions underneath.

## Raw requests

Any endpoint the gem does not wrap, signed, parsed and classified the same way. On POST, `body:` goes in the form
body, as Lazada's signer expects:

```ruby
client.request(:get, "/category/tree/get", query: { language_code: "en_US" })             # app-signed, no token
shop.request(:post, "/product/remove", body: { sku_id_list: ["SkuId_2374791958_13896560193"] }, idempotent: false)
```

## Testing

```sh
bundle install
bundle exec rake          # unit tests, the conformance suite, RuboCop and conformance:verify
```

The default suite makes no network call. It runs every request through `FakeTransport` against fixtures in
`test/fixtures/`; each fixture names its source in `_source` (the documentation page and pull date, or
"recorded live <date>"). The official signing vector (`4190D323…FAB4A`, doc 108069) and the official push example
(`f3d2ca94…6104ab`, doc 120168) are both tests.

The opt-in live tests only read, never refresh a token and never write. Lazada has no sandbox, so they run against a
real authorized store:

```sh
LAZADA_APP_KEY=... LAZADA_APP_SECRET=... LAZADA_ACCESS_TOKEN=... LAZADA_ENDPOINT=ph bundle exec rake test:live
```

Add `LAZADA_RECORD=1` to replace the documentation fixtures with redacted recordings of successful responses. Error
responses are never recorded, and neither is any order response (orders stay on documentation samples); customer
personal data (email, phone, name, nickname, address, recipient and buyer objects) is redacted wherever it appears.

## Contract version

`LazadaRbApi::CONTRACT_VERSION` is `"2"`. The shared interface lives in [CONTRACT.md](CONTRACT.md), which is identical
in all three sibling gems; `test/conformance/` enforces it and `rake conformance:verify` proves the shared files match
`test/conformance/MANIFEST`. Change the contract only in all three gems at once, as CONTRACT.md describes.
