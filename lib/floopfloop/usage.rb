# frozen_string_literal: true

module FloopFloop
  class Usage
    def initialize(client)
      @client = client
    end

    # Returns the full { "plan" => {...}, "credits" => {...},
    # "currentPeriod" => {...} } hash. Not wrapped in a struct — stays
    # forward-compatible if the backend adds fields.
    def summary
      @client.request("GET", "/api/v1/usage/summary")
    end
  end
end
