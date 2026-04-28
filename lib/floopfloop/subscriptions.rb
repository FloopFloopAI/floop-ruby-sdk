# frozen_string_literal: true

module FloopFloop
  # Plan + credit-balance snapshot for the authenticated user.
  #
  # Distinct from {Usage} — `usage.summary` returns current-period
  # consumption (credits remaining + builds used + storage), while
  # `subscriptions.current` returns the plan tier itself (price, billing
  # period, cancel state). They overlap on `monthlyCredits` and
  # `maxProjects` but serve different audiences:
  # `usage.summary` for "am I about to hit my limits?",
  # `subscriptions.current` for "what plan am I on, and when does it
  # renew?".
  class Subscriptions
    def initialize(client)
      @client = client
    end

    # Returns the full
    # `{"subscription" => {...} | nil, "credits" => {...} | nil}` hash.
    # Not wrapped in a struct — stays forward-compatible if the backend
    # adds fields. Both keys are independently nullable: a user may
    # exist without a subscription (mid-signup, cancelled with no grace
    # credits).
    def current
      @client.request("GET", "/api/v1/subscriptions/current")
    end
  end
end
