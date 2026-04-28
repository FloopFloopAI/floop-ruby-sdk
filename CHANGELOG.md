# Changelog

All notable changes to `floopfloop` (Ruby SDK) are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This gem follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) with Ruby's `.alphaN` pre-release convention (e.g. `0.1.0.alpha.1`).

## [0.1.0.alpha.3] — 2026-04-28

### Added
- **`client.subscriptions.current`** — new resource accessor that wraps
  `GET /api/v1/subscriptions/current` and returns the authenticated user's
  plan + credit-balance snapshot. Distinct from `usage.summary` —
  `usage.summary` covers current-period consumption (credits remaining,
  builds used, storage), while `subscriptions.current` returns the plan
  tier itself (price, billing period, cancel state). They overlap on
  `monthlyCredits` and `maxProjects` but serve different audiences ("am I
  about to hit my limits?" vs "what plan am I on, and when does it
  renew?").
- Returns the full
  `{"subscription" => {...} | nil, "credits" => {...} | nil}` hash. Both
  keys are independently nullable: a user may exist without an active
  subscription (mid-signup, cancelled with no grace credits).

### Tests
- Two new cases in `test/resources_test.rb` covering the populated-response
  shape and the both-null edge case.

### Notes
- Mirrors [`@floopfloop/sdk` PR #6](https://github.com/FloopFloopAI/floop-node-sdk/pull/6)
  (Node `0.1.0-alpha.3`) — cross-SDK parity drop.

## [0.1.0.alpha.2] — 2026-04-26

### Fixed
- **`projects.stream` and `projects.wait_for_live` looped until `max_wait`
  timeout when a project entered the `archived` state mid-stream.** The
  `case event["status"]` branch only matched `live` / `failed` /
  `cancelled`; `archived` fell through and the poll continued. Now
  `archived` is treated as a non-error terminal alongside `live`, mirroring
  how Node, Python, Swift, and Kotlin already handle it. (Cross-SDK parity
  fix — the `TERMINAL_PROJECT_STATUSES` constant also now includes
  `archived`. Same drift exists in the Go, Rust, and PHP SDKs and will be
  fixed in their next alpha bumps.)
- `test/stream_test.rb` gains `test_archived_terminates_cleanly_like_live`
  to lock in the regression.

## [0.1.0.alpha.1] — 2026-04-24

### Added
- `FloopFloop::Client.new(api_key:, …)` — Stripe-style entry point with
  resource accessors (`client.projects`, `client.subdomains`,
  `client.secrets`, `client.library`, `client.usage`, `client.api_keys`,
  `client.uploads`, `client.user`). Thread-safe; each request opens its
  own `Net::HTTP` session. Zero runtime dependencies — stdlib `net/http`
  + `json` only.
- `FloopFloop::Error` — single exception class with `#code`, `#status`,
  `#request_id`, `#retry_after`. Unknown server codes pass through in
  `#code`; no subclass-per-code to maintain. `Error.parse_retry_after`
  handles both delta-seconds and RFC 7231 HTTP-date forms, matching the
  Node / Python / Go / Rust SDKs.
- All 8 resources method-for-method parity with the other SDKs:
  - `projects`: `create`, `list`, `get`, `status`, `cancel`, `reactivate`,
    `refine`, `conversations`, `stream`, `wait_for_live`. `stream`
    de-duplicates on `(status, step, progress, queuePosition)` and
    yields every unique snapshot including the terminal event.
  - `subdomains`: `check`, `suggest`.
  - `secrets`: `list`, `set`, `remove`.
  - `library`: `list` (tolerates both bare-array and `{items:[]}`
    response shapes), `clone`.
  - `usage`: `summary`.
  - `api_keys`: `list`, `create`, `remove` (accepts id or name).
  - `uploads`: `create(file_name:, bytes:, file_type:)` (presign +
    direct S3 PUT; 5 MB cap; extension allowlist matching other SDKs)
    and `create_from_path(path)` convenience helper.
  - `user`: `me`.
- Module-level `FloopFloop.new(...)` shortcut for
  `FloopFloop::Client.new(...)`.
- `FloopFloop::Uploads.guess_mime_type(file_name)` public helper for
  callers that want to pre-check before invoking `create`.
- Tests: transport-level (bearer / envelope / error shapes / retry-after
  variants / unknown-code pass-through), every resource, full stream
  sequence with dedupe, `MaxWait` timeout, the refactored
  `wait_for_live`. Run with `rake test`.

### Ruby version

- Minimum supported Ruby: **3.0**. Tested on 3.3.

### CI

- GitHub Actions: `rake test` on Ruby 3.0 / 3.1 / 3.2 / 3.3.
- Release workflow triggers on `v*` tag and publishes to RubyGems via
  `RUBYGEMS_API_KEY` secret. One-time per-repo setup before the first
  tag push.
