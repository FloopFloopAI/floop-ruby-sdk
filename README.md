# floopfloop

[![Gem Version](https://img.shields.io/gem/v/floopfloop?logo=rubygems)](https://rubygems.org/gems/floopfloop)
[![Gem Downloads](https://img.shields.io/gem/dt/floopfloop?logo=rubygems)](https://rubygems.org/gems/floopfloop)
[![CI](https://img.shields.io/github/actions/workflow/status/FloopFloopAI/floop-ruby-sdk/ci.yml?branch=main&logo=github&label=ci)](https://github.com/FloopFloopAI/floop-ruby-sdk/actions/workflows/ci.yml)
[![Ruby version](https://img.shields.io/badge/ruby-%3E%3D%203.0-red?logo=ruby)](./floopfloop.gemspec)
[![License: MIT](https://img.shields.io/github/license/FloopFloopAI/floop-ruby-sdk)](./LICENSE)

Official Ruby SDK for the [FloopFloop](https://www.floopfloop.com) API. Build, refine, and manage FloopFloop projects from any Ruby codebase (Ruby ≥ 3.0). Zero runtime dependencies — stdlib `net/http` + `json`.

## Install

```bash
gem install floopfloop
```

Or in your `Gemfile`:

```ruby
gem "floopfloop", "~> 0.1.0.alpha.1"
```

## Quickstart

Grab an API key: `floop keys create my-sdk` (via the [floop CLI](https://github.com/FloopFloopAI/floop-cli)) or the dashboard → Account → API Keys. Business plan required to mint new keys.

```ruby
require "floopfloop"

client = FloopFloop::Client.new(api_key: ENV.fetch("FLOOP_API_KEY"))

# Create a project and wait for it to go live.
created = client.projects.create(
  prompt:    "A landing page for a cat cafe with a sign-up form",
  name:      "Cat Cafe",
  subdomain: "cat-cafe",
  bot_type:  "site",
)

live = client.projects.wait_for_live(created.fetch("project").fetch("id"))
puts "Live at: #{live['url']}"
```

## Streaming progress

```ruby
client.projects.stream(project_id) do |ev|
  printf("%s (%d/%d) — %s\n", ev["status"], ev["step"], ev["totalSteps"], ev["message"])
end
```

The block is called for every unique status snapshot; duplicates (same `status / step / progress / queuePosition`) are filtered out so you don't see dozens of identical "queued" events. On success returns the final `live` event; raises `FloopFloop::Error` on `BUILD_FAILED` / `BUILD_CANCELLED` / `TIMEOUT`.

If you just want to block until live, `wait_for_live` wraps `stream` and fetches the hydrated project hash:

```ruby
live = client.projects.wait_for_live(project_id)
```

## Error handling

Every call raises `FloopFloop::Error` on non-2xx. Inspect `#code`:

```ruby
begin
  client.projects.status("my-project")
rescue FloopFloop::Error => e
  case e.code
  when "RATE_LIMITED"  then sleep(e.retry_after || 5); retry
  when "UNAUTHORIZED"  then abort "Check your FLOOP_API_KEY."
  else
    warn "[#{e.code} #{e.status}] #{e.message} (request #{e.request_id})"
    raise
  end
end
```

Known codes: `UNAUTHORIZED`, `FORBIDDEN`, `VALIDATION_ERROR`, `RATE_LIMITED`, `NOT_FOUND`, `CONFLICT`, `SERVICE_UNAVAILABLE`, `SERVER_ERROR`, `NETWORK_ERROR`, `TIMEOUT`, `BUILD_FAILED`, `BUILD_CANCELLED`, `UNKNOWN`. Unknown server codes pass through verbatim in `#code`.

## Resources

| Accessor             | Methods |
|---|---|
| `client.projects`    | `create`, `list`, `get`, `status`, `cancel`, `reactivate`, `refine`, `conversations`, `stream`, `wait_for_live` |
| `client.subdomains`  | `check`, `suggest` |
| `client.secrets`     | `list`, `set`, `remove` |
| `client.library`     | `list`, `clone` |
| `client.usage`       | `summary` |
| `client.api_keys`    | `list`, `create`, `remove` (accepts id or name) |
| `client.uploads`     | `create(file_name:, bytes:, file_type: nil)`, `create_from_path(path, file_type: nil)` |
| `client.user`        | `me` |

Method-for-method parity with `@floopfloop/sdk` (Node), `floopfloop` (Python), `floopfloop` (Rust), and `floop-go-sdk` (Go).

## Uploading attachments

```ruby
# From bytes
att = client.uploads.create(
  file_name: "screenshot.png",
  bytes:     File.binread("./screenshot.png"),
)

# Or the one-shot helper — reads the file for you
att = client.uploads.create_from_path("./screenshot.png")

# Drop into a refine call:
client.projects.refine(project_id,
  message: "Redo the landing page based on this screenshot.",
  attachments: [att],
)
```

Max 5 MB per file; allowed: png, jpg, gif, svg, webp, ico, pdf, txt, csv, doc, docx.

## Configuration

```ruby
client = FloopFloop::Client.new(
  api_key:          ENV.fetch("FLOOP_API_KEY"),
  base_url:         "https://staging.floopfloop.com",  # default production URL
  timeout:          60,                                # default 30s
  user_agent_suffix: "myapp/1.2",                      # appended after floopfloop-ruby-sdk/<v>
)
```

`FloopFloop::Client` is thread-safe — each request opens its own `Net::HTTP` session. Reuse a single client across threads / workers without contention.

## Versioning

Follows [Semantic Versioning](https://semver.org/). Breaking changes in `0.x` are called out in [CHANGELOG.md](./CHANGELOG.md) and a new tag is cut with `v<version>`. Tag push triggers the release workflow which publishes to RubyGems.

## License

MIT
