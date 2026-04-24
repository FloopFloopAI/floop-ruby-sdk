# frozen_string_literal: true

require_relative "test_helper"

class TransportTest < Minitest::Test
  include FloopFloop::TestHelpers

  def test_bearer_and_data_envelope_unwrap
    stub_request(:get, "#{BASE_URL}/api/v1/user/me")
      .with(headers: { "Authorization" => "Bearer flp_test", "Accept" => "application/json" })
      .to_return(status: 200, body: '{"data":{"id":"u_1","email":"p@x"}}', headers: { "Content-Type" => "application/json" })

    data = make_client.user.me
    assert_equal "u_1", data["id"]
    assert_equal "p@x", data["email"]
  end

  def test_user_agent_header_has_prefix
    # Matcher-side `with(headers:)` asserts at dispatch time — if the
    # header doesn't match, WebMock raises and the test fails. Avoids
    # the `assert_requested(stub) { block }` form which crashes on
    # Ruby 3.3 / Windows with a stack overflow.
    stub_request(:get, "#{BASE_URL}/api/v1/user/me")
      .with(headers: { "User-Agent" => %r{\Afloopfloop-ruby-sdk/} })
      .to_return(status: 200, body: '{"data":{}}')
    make_client.user.me
  end

  def test_user_agent_suffix_is_appended
    stub_request(:get, "#{BASE_URL}/api/v1/user/me")
      .with(headers: { "User-Agent" => / myapp\/1\.2\z/ })
      .to_return(status: 200, body: '{"data":{}}')
    make_client(user_agent_suffix: "myapp/1.2").user.me
  end

  def test_error_envelope_becomes_typed_error
    stub_request(:get, "#{BASE_URL}/api/v1/user/me")
      .to_return(
        status: 404,
        headers: { "x-request-id" => "req_1" },
        body: '{"error":{"code":"NOT_FOUND","message":"no such user"}}',
      )
    err = assert_raises(FloopFloop::Error) { make_client.user.me }
    assert_equal "NOT_FOUND", err.code
    assert_equal 404, err.status
    assert_equal "no such user", err.message
    assert_equal "req_1", err.request_id
  end

  def test_retry_after_delta_seconds
    stub_request(:get, "#{BASE_URL}/api/v1/user/me")
      .to_return(
        status: 429,
        headers: { "retry-after" => "5" },
        body: '{"error":{"code":"RATE_LIMITED","message":"slow"}}',
      )
    err = assert_raises(FloopFloop::Error) { make_client.user.me }
    assert_equal "RATE_LIMITED", err.code
    assert_in_delta 5.0, err.retry_after, 0.01
  end

  def test_retry_after_http_date_in_past_is_zero
    # Spec: an HTTP-date in the past → retry_after == 0.
    past = "Wed, 21 Oct 2015 07:28:00 GMT"
    stub_request(:get, "#{BASE_URL}/api/v1/user/me")
      .to_return(
        status: 429,
        headers: { "retry-after" => past },
        body: '{"error":{"code":"RATE_LIMITED","message":"slow"}}',
      )
    err = assert_raises(FloopFloop::Error) { make_client.user.me }
    assert_equal 0, err.retry_after
  end

  def test_unknown_server_code_passes_through
    stub_request(:get, "#{BASE_URL}/api/v1/user/me")
      .to_return(status: 418, body: '{"error":{"code":"TEAPOT_MODE","message":"short and stout"}}')
    err = assert_raises(FloopFloop::Error) { make_client.user.me }
    assert_equal "TEAPOT_MODE", err.code
  end

  def test_non_json_5xx_falls_back_to_server_error
    stub_request(:get, "#{BASE_URL}/api/v1/user/me")
      .to_return(status: 500, body: "upstream crashed")
    err = assert_raises(FloopFloop::Error) { make_client.user.me }
    assert_equal "SERVER_ERROR", err.code
    assert_equal 500, err.status
  end

  def test_missing_api_key_raises
    assert_raises(ArgumentError) { FloopFloop::Client.new(api_key: nil) }
    assert_raises(ArgumentError) { FloopFloop::Client.new(api_key: "") }
  end

  def test_base_url_strips_trailing_slash
    c = FloopFloop::Client.new(api_key: "flp_test", base_url: "https://x.example.com/")
    assert_equal "https://x.example.com", c.base_url
  end
end
