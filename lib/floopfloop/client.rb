# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require_relative "version"
require_relative "error"

module FloopFloop
  # Main entry point. Thread-safe (each request opens its own Net::HTTP
  # session); cheap to construct. See README for the full resource map.
  #
  # Typical use:
  #
  #   client = FloopFloop::Client.new(api_key: ENV.fetch("FLOOP_API_KEY"))
  #   project = client.projects.create(prompt: "a crypto RSI dashboard")
  #   live    = client.projects.wait_for_live(project.fetch("project").fetch("id"))
  class Client
    DEFAULT_BASE_URL   = "https://www.floopfloop.com"
    DEFAULT_TIMEOUT    = 30
    USER_AGENT_PREFIX  = "floopfloop-ruby-sdk/#{VERSION}".freeze

    attr_reader :base_url

    def initialize(api_key:, base_url: DEFAULT_BASE_URL, timeout: DEFAULT_TIMEOUT, user_agent_suffix: nil)
      raise ArgumentError, "api_key is required" if api_key.nil? || api_key.empty?

      @api_key    = api_key
      @base_url   = base_url.to_s.sub(%r{/+\z}, "")
      @timeout    = timeout
      @user_agent =
        if user_agent_suffix && !user_agent_suffix.to_s.empty?
          "#{USER_AGENT_PREFIX} #{user_agent_suffix}"
        else
          USER_AGENT_PREFIX.dup
        end
    end

    # ── Resource accessors ──────────────────────────────────────────

    def projects;   @projects   ||= Projects.new(self);   end
    def subdomains; @subdomains ||= Subdomains.new(self); end
    def secrets;    @secrets    ||= Secrets.new(self);    end
    def library;    @library    ||= Library.new(self);    end
    def usage;      @usage      ||= Usage.new(self);      end
    def api_keys;   @api_keys   ||= ApiKeys.new(self);    end
    def uploads;    @uploads    ||= Uploads.new(self);    end
    def user;       @user       ||= UserApi.new(self);    end

    # ── Internal transport ──────────────────────────────────────────

    # @api private
    # Performs the HTTP request, parses the {data:...} envelope, and
    # raises FloopFloop::Error on non-2xx.  Resources call this; user
    # code should not.
    def request(method, path, body: nil, query: nil, raw_body: nil, headers: {})
      uri = URI.parse("#{@base_url}#{path}")
      uri.query = URI.encode_www_form(query) if query && !query.empty?

      req = build_request(method, uri, body, raw_body, headers)
      response = perform(uri, req)

      body_text = response.body || ""
      request_id = response["x-request-id"]

      if response.code.to_i >= 400
        raise parse_error(body_text, response.code.to_i, request_id, response["retry-after"])
      end

      parse_success(body_text)
    end

    # @api private
    # Raw PUT used by the Uploads two-step flow to push bytes to the
    # presigned S3 URL.  Does NOT send the bearer token and does NOT
    # go through the {data:...} envelope — S3 returns empty body on
    # success, XML on error.
    def raw_put(url, body_bytes, content_type:)
      uri = URI.parse(url)
      req = Net::HTTP::Put.new(uri.request_uri)
      req["Content-Type"] = content_type
      req["Content-Length"] = body_bytes.bytesize.to_s
      req.body = body_bytes

      response = open_http(uri).request(req)
      return if response.code.to_i < 400

      snippet = (response.body || "")[0, 512]
      raise FloopFloop::Error.new(
        code: "UNKNOWN",
        message: "uploads: S3 rejected PUT (#{response.code}): #{snippet}",
        status: response.code.to_i,
      )
    end

    private

    def build_request(method, uri, body, raw_body, extra_headers)
      klass =
        case method.to_s.upcase
        when "GET"    then Net::HTTP::Get
        when "POST"   then Net::HTTP::Post
        when "DELETE" then Net::HTTP::Delete
        when "PATCH"  then Net::HTTP::Patch
        else raise ArgumentError, "unsupported HTTP method: #{method}"
        end
      req = klass.new(uri.request_uri)
      req["Authorization"] = "Bearer #{@api_key}"
      req["User-Agent"]    = @user_agent
      req["Accept"]        = "application/json"
      extra_headers.each { |k, v| req[k] = v }
      if !body.nil?
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      elsif raw_body
        req.body = raw_body
      end
      req
    end

    def perform(uri, req)
      open_http(uri).request(req)
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
      raise FloopFloop::Error.new(code: "TIMEOUT", message: "request timed out after #{@timeout}s", status: 0)
    rescue StandardError => e
      raise FloopFloop::Error.new(
        code: "NETWORK_ERROR",
        message: "could not reach #{@base_url} (#{e.class}: #{e.message})",
        status: 0,
      )
    end

    def open_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl     = (uri.scheme == "https")
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http.write_timeout = @timeout if http.respond_to?(:write_timeout=)
      http
    end

    def parse_success(raw)
      return nil if raw.nil? || raw.empty?

      parsed = JSON.parse(raw)
      if parsed.is_a?(Hash) && parsed.key?("data")
        parsed["data"]
      else
        parsed
      end
    rescue JSON::ParserError
      raw
    end

    def parse_error(raw, status, request_id, retry_after_header)
      code = default_code_for_status(status)
      message = "request failed (#{status})"
      begin
        parsed = JSON.parse(raw)
        if parsed.is_a?(Hash) && parsed["error"].is_a?(Hash)
          code    = parsed["error"]["code"]    || code
          message = parsed["error"]["message"] || message
        end
      rescue JSON::ParserError
        # non-JSON body — fall through to default code + message.
      end

      FloopFloop::Error.new(
        code: code,
        message: message,
        status: status,
        request_id: request_id,
        retry_after: FloopFloop::Error.parse_retry_after(retry_after_header),
      )
    end

    def default_code_for_status(status)
      case status
      when 401 then "UNAUTHORIZED"
      when 403 then "FORBIDDEN"
      when 404 then "NOT_FOUND"
      when 409 then "CONFLICT"
      when 422 then "VALIDATION_ERROR"
      when 429 then "RATE_LIMITED"
      when 503 then "SERVICE_UNAVAILABLE"
      else
        status >= 500 ? "SERVER_ERROR" : "UNKNOWN"
      end
    end
  end
end
