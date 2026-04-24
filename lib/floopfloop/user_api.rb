# frozen_string_literal: true

module FloopFloop
  # Named UserApi rather than User to avoid the "User" namespace
  # shadowing any app-level User model callers might already have. The
  # accessor is `client.user` per the parity contract.
  class UserApi
    def initialize(client)
      @client = client
    end

    def me
      @client.request("GET", "/api/v1/user/me")
    end
  end
end
