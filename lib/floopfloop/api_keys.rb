# frozen_string_literal: true

module FloopFloop
  class ApiKeys
    def initialize(client)
      @client = client
    end

    # Returns the array of API key summaries — flattens the
    # {"keys" => [...]} wrapper for callers.
    def list
      data = @client.request("GET", "/api/v1/api-keys")
      data.is_a?(Hash) ? (data["keys"] || []) : (data || [])
    end

    # Returns the IssuedApiKey hash. The "rawKey" field is the ONLY
    # time the full secret leaves the server — surface it once to the
    # user, then discard.
    def create(name:)
      @client.request("POST", "/api/v1/api-keys", body: { name: name })
    end

    # Revoke by id OR by human-readable name. Mirrors the Node SDK's
    # ergonomic shortcut — does a preflight list to resolve the name.
    def remove(id_or_name)
      match = list.find { |k| k["id"] == id_or_name || k["name"] == id_or_name }
      unless match
        raise FloopFloop::Error.new(
          code: "NOT_FOUND",
          message: "API key not found: #{id_or_name}",
          status: 404,
        )
      end
      @client.request("DELETE", "/api/v1/api-keys/#{url_encode(match['id'])}")
      nil
    end

    private

    def url_encode(str)
      str.to_s.each_byte.map do |b|
        if (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) ||
           [0x2D, 0x2E, 0x5F, 0x7E].include?(b)
          b.chr
        else
          format("%%%02X", b)
        end
      end.join
    end
  end
end
