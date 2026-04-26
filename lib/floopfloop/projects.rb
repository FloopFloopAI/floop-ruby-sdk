# frozen_string_literal: true

module FloopFloop
  TERMINAL_PROJECT_STATUSES = %w[live failed cancelled archived].freeze

  class Projects
    def initialize(client)
      @client = client
    end

    # POST /api/v1/projects
    #
    # Input keys: :prompt (required), :name, :subdomain, :bot_type,
    # :is_auth_protected, :team_id. Returns the raw backend shape:
    # { "project" => {...}, "deployment" => {...} }.
    def create(prompt:, **opts)
      body = { prompt: prompt }
      body[:name]            = opts[:name]             if opts.key?(:name)
      body[:subdomain]       = opts[:subdomain]        if opts.key?(:subdomain)
      body[:botType]         = opts[:bot_type]         if opts.key?(:bot_type)
      body[:isAuthProtected] = opts[:is_auth_protected] if opts.key?(:is_auth_protected)
      body[:teamId]          = opts[:team_id]          if opts.key?(:team_id)
      @client.request("POST", "/api/v1/projects", body: body)
    end

    def list(team_id: nil)
      query = team_id ? { teamId: team_id } : nil
      @client.request("GET", "/api/v1/projects", query: query)
    end

    # Fetch a single project by id or subdomain. No dedicated backend route —
    # filters list() locally, matching the other SDKs.
    def get(ref, team_id: nil)
      list(team_id: team_id).find do |p|
        p["id"] == ref || p["subdomain"] == ref
      end.tap do |match|
        unless match
          raise FloopFloop::Error.new(
            code: "NOT_FOUND",
            message: "project not found: #{ref}",
            status: 404,
          )
        end
      end
    end

    def status(ref)
      @client.request("GET", "/api/v1/projects/#{url_encode(ref)}/status")
    end

    def cancel(ref)
      @client.request("POST", "/api/v1/projects/#{url_encode(ref)}/cancel")
      nil
    end

    def reactivate(ref)
      @client.request("POST", "/api/v1/projects/#{url_encode(ref)}/reactivate")
      nil
    end

    # Refine returns one of three response shapes. Rather than raising on
    # "unexpected" ones we return the raw hash — callers can inspect
    # .fetch("queued") / .fetch("processing") to branch. Matches the
    # Python / Go / Node SDKs' behaviour where the caller decides.
    def refine(ref, message:, **opts)
      body = { message: message }
      if opts.key?(:attachments)
        body[:attachments] = opts[:attachments]
      end
      body[:codeEditOnly] = opts[:code_edit_only] if opts.key?(:code_edit_only)
      @client.request("POST", "/api/v1/projects/#{url_encode(ref)}/refine", body: body)
    end

    def conversations(ref, limit: nil)
      query = limit && limit.positive? ? { limit: limit } : nil
      @client.request("GET", "/api/v1/projects/#{url_encode(ref)}/conversations", query: query)
    end

    # Poll the status endpoint, yielding each de-duplicated snapshot to
    # the block until a terminal state (live / failed / cancelled), the
    # max_wait elapses, or the block raises / breaks.
    #
    # @yield [status_hash] every unique event (status/step/progress/queue)
    # @return [Hash] the final status hash on "live"
    # @raise [FloopFloop::Error] BUILD_FAILED / BUILD_CANCELLED / TIMEOUT
    #
    # Events are de-duplicated on (status, step, progress, queuePosition)
    # so callers don't see dozens of identical "queued" snapshots.
    def stream(ref, interval: 2, max_wait: 600)
      deadline  = Time.now + max_wait
      last_key  = nil
      last_event = nil

      loop do
        if Time.now >= deadline
          raise FloopFloop::Error.new(
            code: "TIMEOUT",
            message: "stream: project #{ref} did not reach a terminal state within #{max_wait}s",
          )
        end

        event = status(ref)
        key = dedup_key(event)
        if key != last_key
          last_key = key
          yield(event) if block_given?
        end
        last_event = event

        case event["status"]
        when "live", "archived"
          # Both are terminal-success states. Archived projects are the
          # post-active form (still hydrated, just not running) — matches
          # the Node, Python, Swift, and Kotlin SDKs' handling.
          return event
        when "failed"
          raise FloopFloop::Error.new(
            code: "BUILD_FAILED",
            message: event["message"].to_s.empty? ? "build failed" : event["message"],
          )
        when "cancelled"
          raise FloopFloop::Error.new(
            code: "BUILD_CANCELLED",
            message: event["message"].to_s.empty? ? "build cancelled" : event["message"],
          )
        end

        remaining = deadline - Time.now
        sleep_for = [interval, remaining].min
        sleep(sleep_for) if sleep_for.positive?
      end

      last_event
    end

    # Block until the project reaches 'live' and return the hydrated
    # project hash. Wraps #stream with a no-op block.
    def wait_for_live(ref, interval: 2, max_wait: 600)
      stream(ref, interval: interval, max_wait: max_wait)
      get(ref)
    end

    private

    def dedup_key(event)
      [
        event["status"],
        event["step"],
        event["progress"],
        event["queuePosition"],
      ].join("|")
    end

    def url_encode(str)
      # Matches Node's encodeURIComponent on the characters that can appear
      # in a project ref (UUIDs + subdomain slugs). URI.encode_www_form_component
      # maps spaces to '+', which is wrong for path segments — roll our own.
      str.to_s.each_byte.map do |b|
        if (b >= 0x30 && b <= 0x39) ||    # 0-9
           (b >= 0x41 && b <= 0x5A) ||    # A-Z
           (b >= 0x61 && b <= 0x7A) ||    # a-z
           [0x2D, 0x2E, 0x5F, 0x7E].include?(b) # - . _ ~
          b.chr
        else
          format("%%%02X", b)
        end
      end.join
    end
  end
end
