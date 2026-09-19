# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- **Check:** `bundle exec rake` runs unit tests, the conformance suite, RuboCop and `conformance:verify`. It makes no network call; `rake test:live` is opt-in (credentials in `test/live/live_helper.rb`; Lazada has no sandbox, so it reads a real store).
- **Sibling gems share files.** `CONTRACT.md`, `.rubocop.yml`, `Rakefile`, `Gemfile`, `test/support/fake_transport.rb` and everything in `test/conformance/` are byte-identical copies of `shopee_rb_api` (the canonical copy). Never edit one here: change all three gems together (see "Changing the contract" in `CONTRACT.md`). The per-gem half of the suite is `test/conformance_adapter.rb`.
- **Public surface is enforced.** `test/conformance/contract.rb` lists every public constant and method with its exact parameters; anything extra must be declared in `lib/lazada_rb_api/extensions.rb`. Internal helpers are `private_constant`.
- **Hosts live only in `ENDPOINTS`** (`lib/lazada_rb_api/endpoints.rb`): per-country API host plus the shared consent and token hosts. Token calls go to the token host (`token_base_url:`), a contract-v2 design; until v2 lands in the shared files, three v1 conformance checks (hosts, Client.new parameters, ENDPOINTS shape) fail by design.
- **Errors are classified by `(code, message, detail)`** in `lib/lazada_rb_api/error_table.rb`; `test/fixtures/error_list.json` holds every documented pair and every one must map to a subclass. Lazada API docs are machine-readable at `https://isvconsole.lazada.com/handler/share/apidoc/getApi.json?path=<path>` (guides: `open.lazada.com/handler/share/doc/getDocDetail.json.json?oeid=LZD_DOC&lang=en_US&docId=<id>`).
- **Relist is cross-border only** (`/product/global/update/status`); local sellers use the `products.activate_skus` extension. Captain decision 2026-09-19; Lazada has no local-seller relist endpoint.
- **Fixtures name their source** in `_source` (doc URL and pull date, or "recorded live <date>").
- **Never publish to RubyGems and never tag 1.0** until the live recording round has replaced the doc fixtures.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
