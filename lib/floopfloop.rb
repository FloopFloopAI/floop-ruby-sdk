# frozen_string_literal: true

# Top-level entry point — `require "floopfloop"` pulls everything in.
#
# Typical use:
#
#   require "floopfloop"
#   client = FloopFloop::Client.new(api_key: ENV.fetch("FLOOP_API_KEY"))
#   created = client.projects.create(prompt: "a crypto RSI dashboard for BTC")
#   live    = client.projects.wait_for_live(created.fetch("project").fetch("id"))
#   puts "Live at: #{live['url']}"

require_relative "floopfloop/version"
require_relative "floopfloop/error"
require_relative "floopfloop/client"

require_relative "floopfloop/projects"
require_relative "floopfloop/subdomains"
require_relative "floopfloop/secrets"
require_relative "floopfloop/library"
require_relative "floopfloop/usage"
require_relative "floopfloop/subscriptions"
require_relative "floopfloop/api_keys"
require_relative "floopfloop/uploads"
require_relative "floopfloop/user_api"

module FloopFloop
  # Shortcut so `FloopFloop.new(api_key: ...)` also works in addition to
  # `FloopFloop::Client.new(api_key: ...)`.
  def self.new(**opts)
    Client.new(**opts)
  end
end
