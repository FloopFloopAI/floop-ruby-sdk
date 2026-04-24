# frozen_string_literal: true

require_relative "lib/floopfloop/version"

Gem::Specification.new do |spec|
  spec.name          = "floopfloop"
  spec.version       = FloopFloop::VERSION
  spec.authors       = ["FloopFloop"]
  spec.email         = ["info@floopfloop.com"]

  spec.summary       = "Official Ruby SDK for the FloopFloop API"
  spec.description   = "Build, refine, and manage FloopFloop projects from any Ruby codebase. Stripe-style client with named resources (projects, subdomains, secrets, library, usage, api_keys, uploads, user)."
  spec.homepage      = "https://www.floopfloop.com"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"]      = spec.homepage
  spec.metadata["source_code_uri"]   = "https://github.com/FloopFloopAI/floop-ruby-sdk"
  spec.metadata["changelog_uri"]     = "https://github.com/FloopFloopAI/floop-ruby-sdk/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"]   = "https://github.com/FloopFloopAI/floop-ruby-sdk/issues"
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/floopfloop"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "README.md",
    "CHANGELOG.md",
    "LICENSE",
    "floopfloop.gemspec"
  ]
  spec.require_paths = ["lib"]

  # No runtime deps — stdlib net/http + json are enough.
end
