# frozen_string_literal: true

require_relative "test_helper"

class ProjectsTest < Minitest::Test
  include FloopFloop::TestHelpers

  def test_create_and_status
    stub_request(:post, "#{BASE_URL}/api/v1/projects")
      .with(body: hash_including("prompt" => "a cat cafe", "botType" => "site"))
      .to_return(
        status: 200,
        body: '{"data":{"project":{"id":"p_1","name":"Cat","subdomain":"cat","status":"queued"},"deployment":{"id":"d_1","status":"queued","version":1}}}',
      )
    stub_request(:get, "#{BASE_URL}/api/v1/projects/p_1/status")
      .to_return(status: 200, body: '{"data":{"step":2,"totalSteps":5,"status":"generating","message":"w","progress":0.4}}')

    out = make_client.projects.create(prompt: "a cat cafe", bot_type: "site")
    assert_equal "p_1", out.dig("project", "id")

    ev = make_client.projects.status("p_1")
    assert_equal "generating", ev["status"]
    assert_in_delta 0.4, ev["progress"], 0.001
  end

  def test_list_with_team_id
    stub_request(:get, "#{BASE_URL}/api/v1/projects?teamId=t_1")
      .to_return(status: 200, body: '{"data":[{"id":"p_1","subdomain":"x","status":"live"}]}')
    res = make_client.projects.list(team_id: "t_1")
    assert_equal 1, res.length
    assert_equal "p_1", res.first["id"]
  end

  def test_get_by_subdomain
    stub_request(:get, "#{BASE_URL}/api/v1/projects")
      .to_return(
        status: 200,
        body: '{"data":[{"id":"p_1","subdomain":"alpha","status":"live"},{"id":"p_2","subdomain":"beta","status":"live"}]}',
      )
    got = make_client.projects.get("beta")
    assert_equal "p_2", got["id"]
  end

  def test_get_not_found
    stub_request(:get, "#{BASE_URL}/api/v1/projects")
      .to_return(status: 200, body: '{"data":[]}')
    err = assert_raises(FloopFloop::Error) { make_client.projects.get("ghost") }
    assert_equal "NOT_FOUND", err.code
  end

  def test_cancel_and_reactivate
    stub_request(:post, "#{BASE_URL}/api/v1/projects/p_1/cancel").to_return(status: 200, body: '{"data":{}}')
    stub_request(:post, "#{BASE_URL}/api/v1/projects/p_1/reactivate").to_return(status: 200, body: '{"data":{}}')
    c = make_client
    assert_nil c.projects.cancel("p_1")
    assert_nil c.projects.reactivate("p_1")
  end

  def test_refine_queued
    stub_request(:post, "#{BASE_URL}/api/v1/projects/p_1/refine")
      .with(body: hash_including("message" => "change X"))
      .to_return(status: 200, body: '{"data":{"queued":true,"messageId":"m_1"}}')
    res = make_client.projects.refine("p_1", message: "change X")
    assert_equal true, res["queued"]
    assert_equal "m_1", res["messageId"]
  end

  def test_conversations_forwards_limit
    stub_request(:get, "#{BASE_URL}/api/v1/projects/p_1/conversations?limit=10")
      .to_return(
        status: 200,
        body: '{"data":{"messages":[{"id":"m_1","role":"user","content":"hi"}],"queued":[],"latestVersion":3}}',
      )
    out = make_client.projects.conversations("p_1", limit: 10)
    assert_equal 1, out["messages"].length
    assert_equal 3, out["latestVersion"]
  end

  def test_conversations_without_limit_omits_query
    stub_request(:get, "#{BASE_URL}/api/v1/projects/p_1/conversations")
      .to_return(status: 200, body: '{"data":{"messages":[],"queued":[],"latestVersion":0}}')
    out = make_client.projects.conversations("p_1")
    assert_equal 0, out["latestVersion"]
  end
end
