# frozen_string_literal: true

module FloopFloop
  class Subdomains
    def initialize(client)
      @client = client
    end

    def check(slug)
      @client.request("GET", "/api/v1/subdomains/check", query: { slug: slug })
    end

    def suggest(prompt)
      @client.request("GET", "/api/v1/subdomains/suggest", query: { prompt: prompt })
    end
  end
end
