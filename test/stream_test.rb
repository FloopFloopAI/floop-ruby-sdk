# frozen_string_literal: true

require_relative "test_helper"

class StreamTest < Minitest::Test
  include FloopFloop::TestHelpers

  def test_dedupes_identical_snapshots_and_yields_terminal
    stub_request(:get, "#{BASE_URL}/api/v1/projects/p_1/status").to_return(
      { status: 200, body: '{"data":{"step":1,"totalSteps":3,"status":"queued","message":""}}' },
      { status: 200, body: '{"data":{"step":2,"totalSteps":3,"status":"generating","progress":0.3,"message":""}}' },
      # Duplicate → should be deduped.
      { status: 200, body: '{"data":{"step":2,"totalSteps":3,"status":"generating","progress":0.3,"message":""}}' },
      { status: 200, body: '{"data":{"step":3,"totalSteps":3,"status":"live","message":""}}' },
    )

    seen = []
    result = make_client.projects.stream("p_1", interval: 0.01, max_wait: 5) do |ev|
      seen << ev["status"]
    end
    # queued, generating(0.3), live — the second identical "generating(0.3)"
    # is filtered out.
    assert_equal %w[queued generating live], seen
    assert_equal "live", result["status"]
  end

  def test_failed_raises_typed_error
    stub_request(:get, "#{BASE_URL}/api/v1/projects/p_1/status")
      .to_return(status: 200, body: '{"data":{"step":1,"totalSteps":1,"status":"failed","message":"typecheck failed"}}')
    err = assert_raises(FloopFloop::Error) do
      make_client.projects.stream("p_1", interval: 0.01, max_wait: 5) { |_| }
    end
    assert_equal "BUILD_FAILED", err.code
    assert_equal "typecheck failed", err.message
  end

  def test_cancelled_raises_typed_error
    stub_request(:get, "#{BASE_URL}/api/v1/projects/p_1/status")
      .to_return(status: 200, body: '{"data":{"step":1,"totalSteps":1,"status":"cancelled","message":""}}')
    err = assert_raises(FloopFloop::Error) do
      make_client.projects.stream("p_1", interval: 0.01, max_wait: 5) { |_| }
    end
    assert_equal "BUILD_CANCELLED", err.code
  end

  def test_max_wait_exceeded_raises_timeout
    stub_request(:get, "#{BASE_URL}/api/v1/projects/p_1/status")
      .to_return(status: 200, body: '{"data":{"step":1,"totalSteps":3,"status":"queued","message":""}}')
    err = assert_raises(FloopFloop::Error) do
      # Tiny interval + tiny max_wait forces the deadline branch quickly.
      make_client.projects.stream("p_1", interval: 0.005, max_wait: 0.05) { |_| }
    end
    assert_equal "TIMEOUT", err.code
  end

  def test_wait_for_live_returns_hydrated_project
    stub_request(:get, "#{BASE_URL}/api/v1/projects/p_1/status").to_return(
      { status: 200, body: '{"data":{"step":1,"totalSteps":2,"status":"queued","message":""}}' },
      { status: 200, body: '{"data":{"step":2,"totalSteps":2,"status":"live","message":""}}' },
    )
    stub_request(:get, "#{BASE_URL}/api/v1/projects")
      .to_return(status: 200, body: '{"data":[{"id":"p_1","subdomain":"x","status":"live","url":"https://x.floop.tech"}]}')
    out = make_client.projects.wait_for_live("p_1", interval: 0.01, max_wait: 5)
    assert_equal "https://x.floop.tech", out["url"]
  end
end
