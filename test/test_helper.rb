# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Require order matters on Ruby 3.3 / Windows — webmock must be loaded
# before minitest/autorun or a deep Net::HTTP patching bug trips a
# STACK_OVERFLOW with no error output. Loading them in this order works
# everywhere we've tested (Windows 3.3, Ubuntu CI 3.0-3.3).
require "webmock"
require "minitest/autorun"
require "floopfloop"

# Set up WebMock globally — every test gets net-connect blocked + the
# stub_request / assert_requested helpers available via the WebMock::API
# mixin below. (Using `require "webmock/minitest"` also works on Linux
# but crashes on the Ruby 3.3 Windows RubyInstaller build, so we hook
# Minitest manually here.)
WebMock.enable!
WebMock.disable_net_connect!(allow_localhost: false)

module Minitest
  class Test
    include WebMock::API

    def teardown
      super
      WebMock.reset!
    end
  end
end

BASE_URL = "https://api.test.local"

module FloopFloop
  module TestHelpers
    def make_client(**overrides)
      FloopFloop::Client.new(
        api_key: "flp_test",
        base_url: BASE_URL,
        **overrides,
      )
    end
  end
end
