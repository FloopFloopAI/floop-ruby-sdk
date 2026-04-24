# frozen_string_literal: true

module FloopFloop
  class Library
    def initialize(client)
      @client = client
    end

    # Backend can emit either a bare Array or a {"items" => [...]} envelope —
    # we tolerate both, matching the Node / Python / Go / Rust SDKs.
    def list(**opts)
      query = {}
      query[:botType] = opts[:bot_type] if opts.key?(:bot_type)
      query[:search]  = opts[:search]   if opts.key?(:search)
      query[:sort]    = opts[:sort]     if opts.key?(:sort)
      query[:page]    = opts[:page]     if opts.key?(:page)
      query[:limit]   = opts[:limit]    if opts.key?(:limit)

      data = @client.request("GET", "/api/v1/library", query: query.empty? ? nil : query)
      return data if data.is_a?(Array)
      return data["items"] if data.is_a?(Hash) && data["items"].is_a?(Array)

      raise FloopFloop::Error.new(
        code: "UNKNOWN",
        message: "library list: unrecognised response shape",
      )
    end

    def clone(project_id, subdomain:)
      @client.request(
        "POST",
        "/api/v1/library/#{url_encode(project_id)}/clone",
        body: { subdomain: subdomain },
      )
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
