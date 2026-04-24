# frozen_string_literal: true

module FloopFloop
  class Secrets
    def initialize(client)
      @client = client
    end

    # Returns the array of { "name" => ..., ... } — flattens the
    # { "secrets" => [...] } wrapper for callers.
    def list(ref)
      data = @client.request("GET", "/api/v1/projects/#{url_encode(ref)}/secrets")
      data.is_a?(Hash) ? (data["secrets"] || []) : (data || [])
    end

    def set(ref, name, value)
      @client.request(
        "POST",
        "/api/v1/projects/#{url_encode(ref)}/secrets",
        body: { name: name, value: value },
      )
      nil
    end

    def remove(ref, name)
      @client.request(
        "DELETE",
        "/api/v1/projects/#{url_encode(ref)}/secrets/#{url_encode(name)}",
      )
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
