# The shared interface contract

```ruby
CONTRACT_VERSION = "2"
```

This file is the shared interface of three sibling gems: `shopee_rb_api`, `lazada_rb_api` and `tiktok_shop_rb_api`.
It is byte-identical in all three repositories. `test/conformance/` enforces it, and `rake conformance:verify` proves
that a copy is identical to the canonical one (see "Changing the contract" at the end).

Sources: the shared-interface design approved by the captain on 2026-09-19 ("approve as written"), plus the three
decisions taken the same day:

- `products.relist(product_ids)` joins the first release in all three gems, with the same conventions as `unlist`.
- Hosts are configuration, not code (see "Hosts" below).
- The gems are libraries. They implement each platform faithfully and configurably and bake in no policy of the
  application that uses them: which host, which sandbox, token re-consent schedules and which limit endpoint to rely
  on all belong to the caller.

Version 2 (captain, 2026-09-19, "Contract v2 in all three") adds two things and changes nothing for Shopee: a gem may
take extra `Client.new` keywords that its `EXTENSIONS` declare (§2), and an `ENDPOINTS` entry may name a separate
token host with a `token_base_url:` override (§2 "Hosts").

On 2026-09-20 (captain, RAC-275 follow-up) the Lazada and TikTok rows were brought in line with the gems as built:
text only, no interface change, `CONTRACT_VERSION` stays 2.

"Every gem" means all three.

## 1. Naming and module layout

| Gem | Top-level module | Require |
|---|---|---|
| `shopee_rb_api` | `ShopeeRbApi` | `require "shopee_rb_api"` |
| `lazada_rb_api` | `LazadaRbApi` | `require "lazada_rb_api"` |
| `tiktok_shop_rb_api` | `TiktokShopRbApi` | `require "tiktok_shop_rb_api"` |

Every gem defines the same public constants under its module: `VERSION`, `CONTRACT_VERSION`, `EXTENSIONS`,
`ENDPOINTS`, `Client`, `Shop`, `Auth`, `Grant`, `AuthorizedShop`, `Response`, `ItemError`, `Page`, `Pager`,
`RetryPolicy`, `Webhook`, `WebhookEvent`, `Transport::NetHttp`, the resource classes `Categories`, `Brands`, `Media`,
`Products`, `Stock`, `Prices`, `Orders`, and the error classes in §8. A gem may add only the classes its `EXTENSIONS`
declare. Internal helpers (`Signer`, `Connection`, `Endpoints`, `ErrorTable`, ...) are private constants and are not
part of the contract.

## 2. Configuration and client construction

No global configuration and no `configure` block: one process serves many storefronts. One `Client` exists per app
credential. It is immutable and safe to share across threads.

```ruby
client = ShopeeRbApi::Client.new(          # Lazada/TikTok: same keywords, plus declared ones (below)
  app_key:       "2001887",                # Shopee partner_id | Lazada app_key | TikTok app_key (String or Integer)
  app_secret:    ENV.fetch("SHOPEE_PARTNER_KEY"),  # Shopee partner_key | Lazada/TikTok app_secret
  endpoint:      :sg,                      # a Symbol from the gem's ENDPOINTS table; default per gem
  base_url:      nil,                      # String: any API host; overrides the endpoint's API host
  auth_base_url: nil,                      # String: any consent-page host; overrides the endpoint's auth host
  transport:     ShopeeRbApi::Transport::NetHttp.new(open_timeout: 5, read_timeout: 30),
  clock:         -> { Time.now },          # returns a Time; the only time source for signing and expiries
  logger:        nil,                      # any Logger; debug lines only; secrets are never written
  retry_policy:  ShopeeRbApi::RetryPolicy.none  # opt in with RetryPolicy.new(max_retries: 5)
)
client.app_key      # => "2001887"   (String)
client.endpoint     # => :sg
client.inspect      # => "#<ShopeeRbApi::Client app_key=\"2001887\" endpoint=:sg app_secret=[REDACTED]>"
```

An unknown `endpoint:`, or a `base_url:` / `auth_base_url:` / `token_base_url:` that is not an http(s) URL, raises
`ConfigurationError`.

**Declared constructor keywords.** Besides the keywords above, a gem's `Client.new` may take only optional keywords
that its `EXTENSIONS` declare as `"Client#<keyword>"`, and each has a public reader of the same name. A declared
keyword may sit anywhere in the list; `token_base_url:` follows `auth_base_url:`. The conformance suite checks the
contract's keywords in order, and that every other one is optional and declared.

| Gem | Declared keywords | Why |
|---|---|---|
| Shopee | none | |
| Lazada | `token_base_url:` | its token API is on `auth.lazada.com/rest`, not the API host |
| TikTok | `token_base_url:`, `service_id:` | tokens come from `auth.tiktok-shops.com`; the consent link is keyed by service id (optional; only `authorize_url` needs it, and raises `ConfigurationError` without it) |

**Transport contract.** A transport is any object that responds to
`call(method:, url:, headers:, body:) -> { status: Integer, headers: Hash, body: String }`. `method` is one of
`:get`, `:post`, `:put` or `:delete`. `body` is a `String` or `nil`: the gem serializes JSON and multipart itself, so
the bytes it signed are the bytes it sends. The response `body` is the raw string; the gem parses it and keeps it for
`Response#raw`. Timeouts and network failures raise `TransportError`.

### Hosts

**Hosts are configuration, not code.** Every host a platform documents is selectable through configuration, and any
other URL can replace it:

- Each gem's `ENDPOINTS` constant is the one named-host table: a frozen Hash of
  `Symbol => { api: "https://...", auth: "https://..." }`, the API host and the consent-page host for that name.
- A platform whose token calls (`auth.exchange_code`, `auth.refresh`) go to a third host adds `token: "https://..."`
  to **every** entry and declares `"Client#token_base_url"` in `EXTENSIONS`. Without a `:token` host, token calls go
  to the API host.
- `endpoint:` picks a name. `base_url:` replaces the API host, `auth_base_url:` replaces the consent-page host and
  `token_base_url:` (where declared) replaces the token host, with any URL (a proxy, a new region, a stale sandbox).
- No host URL may appear anywhere in a gem's `lib/` except that table. The conformance suite configures a custom URL
  for every host and checks that every shared call and the consent URL reach only those hosts, token calls the token
  host; it also selects every named host.
- The default endpoint is one named constant, so changing it is a one-line change.

| Gem | `ENDPOINTS` names | Default | Notes |
|---|---|---|---|
| Shopee | `:sg` (partner.shopeemobile.com; consent open.shopee.com), `:cn` (openplatform.shopee.cn; open.shopee.cn), `:br` (openplatform.shopee.com.br; open.shopee.com.br), `:sandbox` (openplatform.sandbox.test-stable.shopee.sg; open.sandbox.test-stable.shopee.com), `:sandbox_cn` (openplatform.sandbox.test-stable.shopee.cn; open.sandbox.test-stable.shopee.cn) | `:sg` | the API host follows where the CALLER'S SERVER runs, not the shop's market |
| Lazada | `:ph`, `:my`, `:sg`, `:th`, `:vn`, `:id` → `api.lazada.<tld>/rest` | `:ph` | the API host follows the shop's country; every entry's consent host is `auth.lazada.com` and its token host `auth.lazada.com/rest` |
| TikTok | `:row`, `:us` | `:row` | every entry's API host is `open-api.tiktokglobalshop.com` and its token host `auth.tiktok-shops.com`; the name picks the consent host (`services.tiktokshop.com` / `services.us.tiktokshop.com`) |

## 3. Per-shop credentials: the shop session

```ruby
shop = client.shop(access_token: token, **locator)
```

A **locator** is the minimum a platform needs, besides the token, to address one shop. Each gem declares its locator
in `Shop::LOCATOR_KEYS`. `client.shop` raises `ArgumentError` when a key is missing or unknown.

| Gem | `Shop::LOCATOR_KEYS` | Why |
|---|---|---|
| Shopee | `[:shop_id]` | `shop_id` is sent and signed on every Shop-type call |
| Lazada | `[]` | one token is one store; the host carries the region |
| TikTok | `[:shop_cipher]` | one token covers several shops; the cipher picks one |

`AuthorizedShop#locator` returns the right Hash, so the caller never has to spell a locator out. `Shop` is
immutable, `shop.locator` returns the frozen Hash, and `shop.inspect` redacts the token.

## 4. Authorization and token refresh

- The gem **stores no tokens** and **never refreshes on its own**.
- `refresh` returns a new `Grant`. The caller must persist **both** tokens in one write before doing anything else.
- No token lifetime is hard-coded. Expiries come from the response and become absolute `Time`s through the injected
  clock.

```ruby
client.auth.authorize_url(redirect_uri: "https://app.example/callback", state: csrf)
  # => String, on the configured consent host. Shopee and Lazada require redirect_uri:. TikTok raises
  #    ArgumentError if redirect_uri: is given, because its redirect is fixed in Partner Center.

grant = client.auth.exchange_code(code: params[:code], **locator)
  # Shopee: exactly one of shop_id: or main_account_id:. Lazada, TikTok: no locator.

grant = client.auth.refresh(refresh_token: stored.refresh_token, **locator)
  # Shopee: exactly one of shop_id: or merchant_id:. Lazada, TikTok: no locator.

grant.access_token               # String
grant.refresh_token              # String
grant.access_token_expires_at    # Time
grant.refresh_token_expires_at   # Time, or nil when the platform does not report it
grant.shop_ids                   # Array<String>: the shops this grant reached, when the response names them
grant.raw                        # Hash, the token response exactly as received
grant.inspect                    # tokens redacted

client.authorized_shops(access_token: nil)   # => Pager of AuthorizedShop
  # Shopee: get_shops_by_partner, every shop authorized to the app; the token is not used.
  # Lazada: /seller/get with the token (one shop). TikTok: /authorization/202309/shops with the token.
  # Lazada and TikTok raise ArgumentError when access_token is nil.

shop_ref = client.authorized_shops(access_token: grant.access_token).first
shop_ref.shop_id                    # String
shop_ref.name                       # String or nil
shop_ref.region                     # "PH" (upper-case)
shop_ref.authorization_expires_at   # Time or nil
shop_ref.locator                    # {shop_id: "14701711"} | {} | {shop_cipher: "ROW_..."}
shop_ref.raw
```

Discovery is a separate call on all three platforms: the auth code is single use, so a second call inside
`exchange_code` could lose the tokens if it failed.

**Declared extensions:** Shopee `auth.exchange_resend_code(resend_code:, **locator)` → `Grant` (lost-token recovery,
live only), and `Grant#merchant_ids` (main-account grants).

## 5. Capabilities: one method per capability

**Argument conventions (every gem):**

1. **Identity arguments are normalized.** `product_id`, `order_id`, `category_id`, `seller_sku` and `title` use these
   names on every platform, accept a String or an Integer, and the gem converts them to the platform's wire type and
   parameter name (`item_id`, `order_sn`, `ItemId`, `product_title`, ...).
2. **Everything else is native.** `**params`, `payload` and `skus` pass through in the platform's own field names and
   casing. The gem does not rename, default, coerce or validate them, apart from batch-size guards.
3. **One method call makes exactly one HTTP request.** The only exception is iterating a `Pager`. The gem never loops
   over ids, splits windows or chains calls.
4. **Writes never auto-chunk.** A write that takes a list raises `ArgumentError` above the platform maximum, which is
   exposed as a constant. The caller chunks.

```ruby
shop.info                                           # => Response   shop / storefront info
shop.limits(**params)                               # => Response   listing limits / prerequisites

shop.categories.list(**params)                      # => Response   category tree
shop.categories.attributes(category_id, **params)   # => Response   one category's attributes
shop.categories.recommend(title:, **params)         # => Response   category suggestion

shop.brands.list(category_id: nil, page_size: nil, cursor: nil, **params)   # => Pager of brand Hashes

shop.media.upload_image(io, filename: nil, **params)  # => Response  (io: any IO; the gem builds the multipart body)

shop.products.create(payload, **params)             # => Response   (TikTok: idempotency_key: in params)
shop.products.get(product_id, **params)             # => Response   includes QC / audit status fields
shop.products.update(product_id, payload, **params) # => Response   the platform's PARTIAL update
shop.products.list(page_size: nil, cursor: nil, **params)   # => Pager of product Hashes
shop.products.find_by_seller_sku(seller_sku)        # => Array<String> product ids (0..n)
shop.products.unlist(product_ids)                   # => Response   per-item failures in #item_errors
shop.products.relist(product_ids)                   # => Response   per-item failures in #item_errors
ShopeeRbApi::Products::UNLIST_BATCH_MAX             # 50 | Lazada 1 | TikTok 20
ShopeeRbApi::Products::RELIST_BATCH_MAX             # 50 | Lazada 1 | TikTok 20

shop.stock.get(product_id, **params)                # => Response
shop.stock.update(product_id, skus)                 # => Response   skus: Array of native SKU hashes
shop.prices.update(product_id, skus)                # => Response

shop.orders.list(page_size: nil, cursor: nil, **params)     # => Pager of order Hashes (read-only)
shop.orders.get(order_id, **params)                 # => Response   (read-only)
```

**What each shared method calls:**

| Method | Shopee | Lazada | TikTok Shop |
|---|---|---|---|
| `info` | `GET /api/v2/shop/get_shop_info` | `GET /seller/get` | `GET /authorization/202309/shops`; `data` = the element whose `cipher` matches |
| `limits` | `GET /api/v2/product/get_item_limit` (`category_id` optional) | `getPreQcRules`; `GetSellerItemLimit` is the declared extension `shop.item_limit` (cross-border sellers only; the caller chooses) | `GET /product/202312/prerequisites` |
| `categories.list` | `get_category` | `/category/tree/get` | `GET /product/202309/categories` |
| `categories.attributes` | `get_attribute_tree` (`category_id_list` = [id]) | `/category/attributes/get` (`primary_category_id`) | `GET /product/202309/categories/{id}/attributes` |
| `categories.recommend` | `category_recommend` (`item_name`) | `/product/category/suggestion/get` (`product_name`; `image_url` required in params) | `POST /product/202309/categories/recommend` (`product_title`) |
| `brands.list` | `get_brand_list` (`category_id` required) | `/category/brands/query` (raises `ArgumentError` if `category_id` is given: Lazada brands are per region) | `GET /product/202309/brands` |
| `media.upload_image` | `POST /api/v2/media_space/upload_image` (Public-signed) | `POST /image/upload` | `POST /product/202309/images/upload` (`use_case` required in params) |
| `products.create` | `POST add_item` | `POST /product/create` (the gem wraps `{"Request":{"Product":…}}`) | `POST /product/202309/products` |
| `products.get` | `get_item_base_info` (`item_id_list` = [id]) | `/product/item/get` | `GET /product/202309/products/{id}` |
| `products.update` | `POST update_item` | `POST /product/update` (the gem sets `ItemId`) | `POST /product/202509/products/{id}/partial_edit` |
| `products.list` | `get_item_list` | `/products/get` (offset paging; `PaginationLimitError` at Lazada's offset cap of 10,000) | `POST /product/202502/products/search` |
| `products.find_by_seller_sku` | `search_item(item_sku:)`: item-level SKU only | `/products/get` `filter=all`, `sku_seller_list=[sku]` | `products/search` `{seller_skus: [sku]}` |
| `products.unlist` | `unlist_item` `[{item_id, unlist: true}]` | `/product/deactivate` (one `ItemId`) | `POST /product/202309/products/deactivate` |
| `products.relist` | `unlist_item` `[{item_id, unlist: false}]` | `POST /product/global/update/status` (`type=single`, `status=upShelf`; one product per call). **Cross-border sellers only**: Lazada documents no relist endpoint for local sellers, who use the extension `products.activate_skus` | `POST /product/202309/products/activate` (re-audited) |
| `stock.get` | `get_model_list` (items without models: stock is on `products.get` `stock_info_v2`) | `/product/item/get` (`skus[].quantity`, `Available`) | `POST /product/202309/inventory/search` (`product_ids` = [id]) |
| `stock.update` | `update_stock` (≤50) | `/product/price_quantity/update` quantity fields (≤50) | `POST .../products/{id}/inventory/update` |
| `prices.update` | `update_price` (≤50) | `/product/price_quantity/update` price fields | `POST .../products/{id}/prices/update` |
| `orders.list` | `get_order_list` (window ≤15 d, else `ArgumentError`) | `/orders/get` | `POST /order/202309/orders/search` |
| `orders.get` | `get_order_detail` (`order_sn_list` = id) | `/order/get` | `GET /order/202507/orders` (`ids` = id) |

**Declared platform extensions.** Each gem lists its own in `EXTENSIONS`, a frozen Hash of `"Class#member" =>
description`. When two gems need the same thing, they use the same name. The conformance suite fails on any public
method or constant that is neither in this contract nor declared.

| Gem | Extension | Endpoint | Why it cannot be shared |
|---|---|---|---|
| Shopee | `shop.variants.init(product_id, payload)` | `init_tier_variation` | Shopee publishes in two calls; the others carry variants inside create |
| Shopee | `shop.variants.update_tiers(product_id, payload)` | `update_tier_variation` | the non-destructive re-tier |
| Shopee | `shop.variants.list(product_id)` | `get_model_list` | model ids exist only on Shopee |
| Shopee | `shop.categories.variations(category_id)` | `get_variation_tree` | standard variation vocabulary |
| Shopee | `shop.attributes.search_values(attribute_id:, **params)` → Pager | `search_attribute_value_list` | large enums |
| Shopee | `shop.logistics_channels` | `get_channel_list` | `logistic_info` is required on `add_item` |
| Shopee, TikTok | `shop.warehouses` | `get_warehouse_detail` / `GET /logistics/202309/warehouses` | `location_id` / `warehouse_id` is required on stock entries; Lazada needs neither |
| Shopee | `shop.certification_rules(category_id:, attribute_list:)` | `get_product_certification_rule` | category-gated certification |
| Shopee | `shop.products.violations(product_ids)` | `get_item_violation_info` | the diagnosis loop |
| Shopee, TikTok | `shop.products.diagnoses(product_ids)` | `get_item_content_diagnosis_result` / `GET /product/202405/products/diagnoses` | Lazada has no per-id equivalent |
| Lazada | `shop.products.qc_alerts(**params)` → Pager | `/product/qc/alert/list` | Lazada's QC signal is a list, not per id |
| Lazada | `shop.products.activate_skus(product_id, sku_ids)` | `POST /product/update` with each SKU's `Status` `"active"` | local sellers have no relist endpoint, so they reactivate SKUs; `relist` serves cross-border sellers only |
| Lazada | `shop.item_limit` | `GET /product/seller/item/limit` (`GetSellerItemLimit`) | documented for cross-border sellers only; the caller chooses between it and `limits` |
| Lazada | `shop.orders.items(order_id)` | `/order/items/get` | Lazada splits order lines from the header |
| TikTok | `shop.products.replace(product_id, payload)` | `PUT /product/202509/products/{id}` | full replace; omitted SKUs are **deleted** |
| TikTok | `shop.products.check_listing(payload)` | `POST /product/202309/products/listing_check` | the only remote dry run |
| TikTok | `shop.categories.rules(category_id, **params)` | `GET /product/202309/categories/{id}/rules` | feeds `limits` |
| Lazada, TikTok | `Client.new(token_base_url:)` and `client.token_base_url` | the token host (Lazada `auth.lazada.com/rest`, TikTok `auth.tiktok-shops.com`) | the token calls are not on the API host (see "Declared constructor keywords") |
| TikTok | `Client.new(service_id:)` and `client.service_id` | keys the seller consent link | only `auth.authorize_url` needs it |

**Deliberately out of the first release** (reachable through `request`): delete/remove/recover, Shopee
`batch_add_item`, add/update/delete model and vehicles; Lazada video, image migration, SKU removal, `/images/set`,
cascade properties, content score, `/product/pre/check`; TikTok global products, AI suggestions, size charts; and every
platform's webhook-subscription API.

## 6. Return shapes

Every non-paged method returns a `Response`, identical in every gem:

```ruby
res.data          # frozen Hash or Array, string keys, the platform's payload VERBATIM with the envelope removed
res.request_id    # String or nil
res.warnings      # Array<String>: Shopee "warning"; TikTok data.warnings[].message; Lazada []
res.item_errors   # Array<ItemError>: Shopee failure_list / fail_error; TikTok data.errors[];
                  #   Lazada data.update_ic_product_fail_result_list[] (relist), else []
res.http_status   # Integer
res.endpoint      # String, the signed path, e.g. "/api/v2/product/add_item"
res.raw           # frozen Hash, the parsed body exactly as received

ItemError = Data.define(:id, :code, :message, :raw)   # id and code are Strings ("" when the platform gives none)
```

The gem's own value objects (`Grant`, `AuthorizedShop`, `WebhookEvent`, `Page`, `ItemError`, `Response`) are `Data`
classes. They are the **only** place the gem normalizes: ids become Strings, times become UTC `Time`s, and secrets are
redacted in `inspect`. Platform data inside `data` and `raw` is never coerced.

## 7. Pagination

```ruby
pager = shop.products.list(page_size: 100, item_status: ["NORMAL"])   # native filter
pager.each { |product_hash| ... }          # every item, fetching pages lazily
pager.lazy.first(10)                       # fetches only as many pages as needed
pager.each_page { |page| ... }             # page.items, page.next_cursor, page.total, page.response
page = pager.first_page
shop.products.list(page_size: 100, item_status: ["NORMAL"], cursor: page.next_cursor)   # resume later
```

- `Pager` includes `Enumerable`. `each` and `each_page` without a block return `Enumerator`s.
- `Page = Data.define(:items, :next_cursor, :total, :response)`. `next_cursor` is an **opaque String**, or nil on the
  last page. Callers may store it and pass it back as `cursor:`, but must never parse it.
- `page_size:` defaults to the platform maximum for that endpoint. A larger value raises `ArgumentError`.
- Stop conditions are per endpoint and internal. An empty or missing token both mean the end.
- Hard caps end iteration with `PaginationLimitError`, so a truncated walk is never silent. Splitting the window is
  the caller's job.

## 8. Errors and retry semantics

```
<Gem>::Error < StandardError
├── ConfigurationError          # bad keyword, unknown endpoint, malformed host URL, missing service_id, …
├── TransportError              # timeout, connection reset, TLS; no platform response was read
├── PaginationLimitError        # a platform hard cap stopped a Pager
├── WebhookSignatureError       # inbound webhook failed verification
└── ApiError                    # the platform answered with an error
    ├── AuthenticationError     # this shop's token is invalid or expired, or the token and shop don't match
    ├── AppCredentialsError     # app key or secret invalid, app deleted or restricted → every shop is down
    ├── PermissionError         # scope or API permission, IP allow-list, seller or shop inactive or banned, KYC
    ├── SignatureError          # the platform rejected our signature or timestamp (a gem bug or clock skew)
    ├── RateLimitError          # throttled; not executed
    ├── QuotaExceededError      # daily app quota exhausted; not executed
    ├── ConcurrencyError        # a concurrent edit was refused; not executed
    ├── ServerError             # platform 5xx or internal error; outcome UNKNOWN for writes
    ├── RequestError            # malformed request: missing param, bad path, method, version or content type
    └── BusinessError           # a documented business rejection: validation, content, entitlement, not found
```

Every `ApiError` carries `#code` (String), `#message`, `#request_id`, `#http_status`, `#endpoint`, `#detail` (Array),
`#response` (the `Response`, when the body parsed), `#retry_after` (Float seconds or nil) and `#retryable?`.

- **Classification is data.** Each gem keeps an ordered `ErrorTable` of `(code, message pattern) → class`, built from
  the documented error lists, matching on code **and** message because platforms overload codes. A code the table
  does not map raises plain `ApiError`: the gem never guesses a subclass.
- **`retryable?`**:
  - `true` for `RateLimitError`, `QuotaExceededError` (after `retry_after`) and `ConcurrencyError`.
  - For `ServerError` and `TransportError`, `true` **only when the request was idempotent**. Reads are idempotent.
    Of the writes, `stock.update`, `prices.update`, `products.unlist` and `products.relist` are idempotent because
    they set absolute state, and so is a TikTok create that carries `idempotency_key:`. `create`, `update`,
    `upload_image` and every Shopee variant call are not. `request(..., idempotent: true)` declares it for the
    escape hatch.
  - `false` for everything else.
- **`retry_after`** comes from a `Retry-After` header (seconds or an HTTP date), a documented hint, or the time left
  until the quota resets (Shopee `error_limit`: 00:00 UTC+8).
- **`RetryPolicy`**: `RetryPolicy.none` is the default. `RetryPolicy.new(max_retries: 5, base: 1.0, cap: 60.0,
  jitter: 0.5, sleeper: ->(s) { sleep(s) })` retries only errors whose `retryable?` is true, waiting
  `max(retry_after, min(base * 2**n + rand(jitter), cap))`. Every retry re-stamps and re-signs the request.
  Public methods: `max_retries`, `delay_for(error, attempt)`, `run { }`.
- The gem **never** refreshes a token in response to `AuthenticationError`.

## 9. Webhooks: verify and parse

```ruby
<Gem>::Webhook.verify(raw_body:, signature:, app_key:, app_secret:, url: nil)   # => true | false (pure, no HTTP)
<Gem>::Webhook.parse(raw_body)                                                  # => WebhookEvent

event = client.verify_webhook(raw_body: request.raw_post,
                              signature: request.headers["Authorization"],
                              url: callback_url)        # url: required by Shopee, ignored by the others
                                                        # raises WebhookSignatureError

event.type          # :authorization_expiring | :deauthorized | :product_status | :other
event.code          # String, the platform's own event code: Shopee "12", Lazada "8", TikTok "7", …
event.shop_id       # String or nil
event.occurred_at   # Time
event.data          # frozen Hash, verbatim
event.raw
```

- The signature is computed over the **raw body bytes as received**, never re-serialized JSON. The comparison is
  constant-time and case-insensitive on hex.
- Shopee: `HMAC(partner_key, url + "|" + raw_body)`; `url:` is the callback URL registered in the console and
  `verify` raises `ArgumentError` when it is nil. Lazada and TikTok: `HMAC(app_secret, app_key + raw_body)`.
- Type mapping: `:authorization_expiring` = Shopee code 12, Lazada message_type 8, TikTok type 7
  (`UPCOMING_AUTHORIZATION_EXPIRATION`); `:deauthorized` = TikTok type 6 (`SELLER_DEAUTHORIZATION`) and Shopee code 2;
  `:product_status` = Lazada message_type 1 (QC) and TikTok types 5 and 37; anything else `:other`, with `code` set.
- Replying to the webhook (Shopee: 2xx with an **empty body**; Lazada: an OV/EV certificate) is the application's
  job. Each README states it.

## 10. The raw-request escape hatch

```ruby
client.request(:get, "/api/v2/public/get_shops_by_partner", query: { page_no: 1 })        # app-level
shop.request(:post, "/api/v2/product/delete_item", body: { item_id: 1 }, idempotent: false)
# => Response. Signed, sent, parsed and classified exactly like a wrapped method.
```

`path` is the platform's signed path. `query:` and `body:` are native. `idempotent:` defaults to true for `:get` and
false otherwise, and feeds `retryable?`. The escape hatch obeys the one-request rule.

## 11. Logging and secrets

- The gem logs only at `debug`: method, endpoint, HTTP status, `request_id` and duration.
- It never logs, nor puts in an exception message or `inspect`/`pp` output: the app secret / partner key, `sign`,
  `access_token`, `refresh_token`, the auth code or the resend code.

## Changing the contract

The contract changes only through `test/conformance/contract.rb`, and only as one change in all three gems in one
sitting:

1. Edit `contract.rb`, this file, and any other shared file, identically in the three repositories.
2. Bump `CONTRACT_VERSION` in all three gems (this file and `lib/<gem>/version.rb`).
3. Run `rake conformance:manifest` in each gem, then compare `test/conformance/MANIFEST` across the three checkouts:
   they must be identical before any main branch moves.

`rake` runs `conformance:verify` by default, so editing a shared file in one gem alone fails that gem's build.
