# Cookbook

Concrete `floopfloop` (RubyGems) patterns you can copy-paste. Every snippet uses only the SDK's public surface — no undocumented endpoints, no private helpers.

For the basics (install, client setup, resource tour) see the [README](../README.md). This file is the **"I know the basics, now how do I actually build X"** layer.

These recipes mirror the [Node](https://github.com/FloopFloopAI/floop-node-sdk/blob/main/docs/recipes.md), [Python](https://github.com/FloopFloopAI/floop-python-sdk/blob/main/docs/recipes.md), [Go](https://github.com/FloopFloopAI/floop-go-sdk/blob/main/docs/recipes.md), and [Rust](https://github.com/FloopFloopAI/floop-rust-sdk/blob/main/docs/recipes.md) cookbooks, translated to Ruby idioms (keyword args, block-based stream, `rescue FloopFloop::Error`).

---

## 1. Ship a project from prompt to live URL

The canonical one-call flow: create, wait, done. `wait_for_live` raises `FloopFloop::Error` with `code: "BUILD_FAILED"` / `"BUILD_CANCELLED"` / `"TIMEOUT"` on non-success terminals, so a plain `begin/rescue` is enough.

```ruby
require "floopfloop"

client = FloopFloop::Client.new(api_key: ENV.fetch("FLOOP_API_KEY"))

def ship(client, prompt:, subdomain:)
  created = client.projects.create(
    prompt: prompt,
    subdomain: subdomain,
    bot_type: "site",
  )
  project_id = created["project"]["id"]

  # Polls status every 2s; bounds the total wait to 10 minutes so a
  # stuck build doesn't hang forever.
  live = client.projects.wait_for_live(project_id, interval: 2, max_wait: 600)
  live["url"]
rescue FloopFloop::Error => e
  warn("build failed: #{e.message}") if e.code == "BUILD_FAILED"
  raise
end

url = ship(client,
  prompt: "A single-page portfolio for a landscape photographer",
  subdomain: "landscape-portfolio",
)
puts "Live at #{url}"
```

`max_wait` is in **seconds**, not milliseconds — matches `Time` arithmetic everywhere else in Ruby. The default is 600 seconds (10 minutes).

**When to prefer `stream` over `wait_for_live`:** when you want to show progress to a user. `wait_for_live` only returns at the end — no visibility into what the build is doing.

---

## 2. Watch a build progress in real time

`projects.stream(ref) { |event| ... }` yields each de-duplicated status snapshot to the block until a terminal state (`live` / `failed` / `cancelled`) or `max_wait` elapses. Events are de-duplicated on `(status, step, progress, queuePosition)` so the block doesn't fire on every poll.

```ruby
require "floopfloop"

client = FloopFloop::Client.new(api_key: ENV.fetch("FLOOP_API_KEY"))

created = client.projects.create(
  prompt: "A recipe blog with a dark theme",
  subdomain: "recipe-blog",
  bot_type: "site",
)
project_id = created["project"]["id"]

begin
  client.projects.stream(project_id) do |event|
    progress = event["progress"] ? " #{event['progress'].to_i}%" : ""
    step     = event["step"]     ? " — #{event['step']}"      : ""
    puts "[#{event['status']}]#{progress}#{step}"
  end
rescue FloopFloop::Error => e
  case e.code
  when "BUILD_FAILED"    then abort("build failed: #{e.message}")
  when "BUILD_CANCELLED" then abort("user cancelled build")
  when "TIMEOUT"         then abort("build stalled past max_wait")
  else raise
  end
end

# Reached "live" cleanly — fetch the hydrated project.
done = client.projects.get(project_id)
puts "Live at #{done['url']}"
```

**Early abort.** Raise an error from inside the block. `stream` doesn't swallow exceptions, so they propagate to your `rescue`:

```ruby
class EnoughProgress < StandardError; end

begin
  client.projects.stream("recipe-blog") do |event|
    raise EnoughProgress if event["progress"] && event["progress"] >= 50
    puts "[#{event['status']}] #{event['progress']}%"
  end
rescue EnoughProgress
  puts "saw enough progress, moving on"
end
```

`break value` from inside the block also works and makes `stream` return `value`, but a custom exception class is the more legible signal — it survives refactors that rearrange the loop.

---

## 3. Refine a project, even when it's mid-build

`projects.refine` returns the raw hash from the backend. Three mutually-exclusive shapes:

- `{"queued" => true, "messageId" => "..."}` — project is currently deploying; your message is queued and will be processed when the current build finishes.
- `{"processing" => true, "deploymentId" => "...", "queuePriority" => N}` — your message triggered a new build immediately.
- `{"queued" => false}` — saved as a conversation entry without triggering a build.

```ruby
require "floopfloop"

client = FloopFloop::Client.new(api_key: ENV.fetch("FLOOP_API_KEY"))

result = client.projects.refine("recipe-blog", message: "Add a search bar to the header")

case
when result["processing"]
  puts "Build started (deployment #{result['deploymentId']})"
  client.projects.wait_for_live("recipe-blog")
when result["queued"]
  puts "Queued behind current build (message #{result['messageId']})"
  # Poll once — when "live", your queued message has been processed.
  client.projects.wait_for_live("recipe-blog")
else
  puts "Saved as a chat message, no build triggered"
end
```

Unlike Node / Python / Go / Rust, the Ruby SDK doesn't yet expose a typed `RefineResult` — `refine` returns the raw decoded JSON. Keys stay camelCase since they come straight from the wire.

---

## 4. Upload an image and refine with it as context

Uploads are two-step: `uploads.create` (or the disk-reading shortcut `uploads.create_from_path`) presigns an S3 URL and PUTs the bytes for you, returning an attachment hash you can drop directly into `refine`'s `:attachments` array. **No type conversion needed** — unlike Go/Rust, the Ruby SDK uses the same hash shape on both sides.

```ruby
require "floopfloop"

client = FloopFloop::Client.new(api_key: ENV.fetch("FLOOP_API_KEY"))

# Convenience helper — reads the file for you.
attachment = client.uploads.create_from_path("./mockup.png")

# Or pass bytes directly if you already have the payload:
# bytes = File.binread("./mockup.png")
# attachment = client.uploads.create(file_name: "mockup.png", bytes: bytes)

client.projects.refine(
  "recipe-blog",
  message: "Make the homepage look like this mockup.",
  attachments: [attachment],
)
```

**Supported types:** `png`, `jpg/jpeg`, `gif`, `svg`, `webp`, `ico`, `pdf`, `txt`, `csv`, `doc`, `docx`. Max 5 MB per upload. The SDK validates client-side before hitting the network, so bad inputs raise `FloopFloop::Error` with `code: "VALIDATION_ERROR"` and no round-trip.

Attachments only flow through `refine` today — `create` doesn't accept them via the SDK. If you need to anchor a brand-new project against images, create with a prompt first, then refine with the attachments as a follow-up.

---

## 5. Rotate an API key from a CI job

Three-step rotation: create the new key, write it to your secret store, then revoke the old one. The order matters — you must revoke with a **different** key than the one making the call (the backend returns `400 VALIDATION_ERROR` if you try to revoke the key you're authenticated with).

```ruby
require "floopfloop"

def rotate(victim_name)
  # Use a long-lived bootstrap key (stored as a CI secret) to do the
  # rotation. Don't use the key we're about to revoke — that hits the
  # self-revoke guard.
  bootstrap = FloopFloop::Client.new(api_key: ENV.fetch("FLOOP_BOOTSTRAP_KEY"))

  # 1. Find the key we want to rotate by its name. (Each name is unique
  #    per account because the dashboard enforces it; matching by name
  #    is more reliable than matching the prefix substring.)
  keys = bootstrap.api_keys.list
  victim = keys.find { |k| k["name"] == victim_name }
  raise "key not found: #{victim_name}" if victim.nil?

  # 2. Mint the replacement.
  fresh = bootstrap.api_keys.create(name: "#{victim_name}-new")
  write_secret("FLOOP_API_KEY", fresh["rawKey"])

  # 3. Revoke the old one. remove() accepts an id OR a name.
  bootstrap.api_keys.remove(victim["id"])
end

# Wire write_secret into your CI's secret store — AWS Secrets Manager,
# Vault, GitHub Actions `gh secret set`, etc.
def write_secret(name, value)
  # ...
end
```

**Can't I just reuse the bootstrap key forever?** Technically yes — if it's tightly scoped and audited. In practice, a single long-lived "rotator key" is a common compromise: it only has permission to mint/list/revoke keys, never appears in application traffic, and itself gets rotated manually on a rare cadence (annually, or on compromise).

The 5-keys-per-account cap applies to active keys, so make sure to revoke old rotations rather than accumulating them.

---

## 6. Retry with backoff on `RATE_LIMITED` and `NETWORK_ERROR`

`FloopFloop::Error` carries everything you need to implement backoff correctly:

- `#retry_after` — populated from the `Retry-After` header on 429s (parsed from delta-seconds OR HTTP-date), in **seconds** (Float or Integer). `nil` when the server didn't set it.
- `#code` — distinguishes retryable (`RATE_LIMITED`, `NETWORK_ERROR`, `TIMEOUT`, `SERVICE_UNAVAILABLE`, `SERVER_ERROR`) from permanent (`UNAUTHORIZED`, `FORBIDDEN`, `VALIDATION_ERROR`, `NOT_FOUND`, `CONFLICT`, `BUILD_FAILED`, `BUILD_CANCELLED`).

```ruby
require "floopfloop"

RETRYABLE = %w[
  RATE_LIMITED
  NETWORK_ERROR
  TIMEOUT
  SERVICE_UNAVAILABLE
  SERVER_ERROR
].freeze

def with_retry(max_attempts: 5)
  attempt = 0
  begin
    attempt += 1
    yield
  rescue FloopFloop::Error => e
    raise unless RETRYABLE.include?(e.code)
    raise if attempt >= max_attempts

    # Prefer the server's hint; fall back to exponential backoff
    # with jitter capped at 30 s.
    server_hint = e.retry_after
    expo        = [30.0, 0.25 * (2**attempt)].min
    jitter      = rand(0.25)
    wait        = (server_hint || expo) + jitter

    request_tag = e.request_id ? " — request #{e.request_id}" : ""
    warn("floop: #{e.code} (attempt #{attempt}/#{max_attempts}), " \
         "retrying in #{wait.round(2)}s#{request_tag}")
    sleep(wait)
    retry
  end
end

# Wrap any SDK call:
projects = with_retry { client.projects.list }
```

**Don't retry everything.** `VALIDATION_ERROR`, `UNAUTHORIZED`, and `FORBIDDEN` are not going to fix themselves between attempts — retrying them just burns rate-limit budget and delays the real error reaching your logs.

**`retry_after` is in seconds, not milliseconds** — this differs from the Node / Python SDKs (which expose `retryAfterMs` / `retry_after_ms`). `Time.now + e.retry_after` gives you the unblock time directly without unit conversion.

---

## Got a pattern worth adding?

Open an issue at [FloopFloopAI/floop-ruby-sdk/issues](https://github.com/FloopFloopAI/floop-ruby-sdk/issues) describing the use case. Recipes live in this file, not in `lib/`, so they're easy to update without a gem release.
