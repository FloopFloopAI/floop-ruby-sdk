# frozen_string_literal: true

module FloopFloop
  # Single exception type raised on every non-2xx response and on network /
  # timeout failures.  Inspect `#code` (a String matching the taxonomy the
  # Node / Python / Go / Rust SDKs share) to branch, not the class — unknown
  # server codes pass through verbatim in `#code` rather than raising a
  # subclass we'd have to keep in sync.
  #
  # Known codes: UNAUTHORIZED, FORBIDDEN, VALIDATION_ERROR, RATE_LIMITED,
  # NOT_FOUND, CONFLICT, SERVICE_UNAVAILABLE, SERVER_ERROR, NETWORK_ERROR,
  # TIMEOUT, BUILD_FAILED, BUILD_CANCELLED, UNKNOWN.
  #
  # Example:
  #
  #   begin
  #     client.projects.status("p_1")
  #   rescue FloopFloop::Error => e
  #     case e.code
  #     when "RATE_LIMITED"  then sleep(e.retry_after || 5)
  #     when "UNAUTHORIZED"  then abort "Check your FLOOP_API_KEY."
  #     else raise
  #     end
  #   end
  class Error < StandardError
    attr_reader :code, :status, :request_id, :retry_after

    def initialize(code:, message:, status: 0, request_id: nil, retry_after: nil)
      @code        = code
      @status      = status
      @request_id  = request_id
      @retry_after = retry_after
      super(message)
    end

    def to_s
      parts = +"floop: ["
      parts << code
      parts << " #{status}" unless status.nil? || status.zero?
      parts << "] #{message}"
      parts << " (request #{request_id})" if request_id
      parts
    end

    # Parse a Retry-After header value per RFC 7231 — accepts either
    # delta-seconds or HTTP-date.  Returns nil on unparseable / empty.
    def self.parse_retry_after(header)
      return nil if header.nil? || header.empty?

      begin
        secs = Float(header)
        return nil if secs.negative?

        return secs
      rescue ArgumentError
        # Fall through to HTTP-date parsing.
      end

      begin
        require "time"
        when_ = Time.httpdate(header)
        delta = when_ - Time.now
        return [delta, 0].max
      rescue ArgumentError
        nil
      end
    end
  end
end
