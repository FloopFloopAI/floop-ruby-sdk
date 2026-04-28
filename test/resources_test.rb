# frozen_string_literal: true

require_relative "test_helper"

class ResourcesTest < Minitest::Test
  include FloopFloop::TestHelpers

  # ── subdomains ────────────────────────────────────────────────────

  def test_subdomains_check_and_suggest
    stub_request(:get, "#{BASE_URL}/api/v1/subdomains/check?slug=hello")
      .to_return(status: 200, body: '{"data":{"slug":"hello","available":true}}')
    stub_request(:get, "#{BASE_URL}/api/v1/subdomains/suggest?prompt=a%20cat%20cafe")
      .to_return(status: 200, body: '{"data":{"slug":"cat-cafe"}}')
    c = make_client
    r1 = c.subdomains.check("hello")
    assert_equal true, r1["available"]
    r2 = c.subdomains.suggest("a cat cafe")
    assert_equal "cat-cafe", r2["slug"]
  end

  # ── secrets ───────────────────────────────────────────────────────

  def test_secrets_list_set_remove
    stub_request(:get, "#{BASE_URL}/api/v1/projects/p_1/secrets")
      .to_return(status: 200, body: '{"data":{"secrets":[{"name":"STRIPE_KEY"},{"name":"DB_URL"}]}}')
    stub_request(:post, "#{BASE_URL}/api/v1/projects/p_1/secrets")
      .with(body: hash_including("name" => "STRIPE_KEY", "value" => "sk_xxx"))
      .to_return(status: 200, body: '{"data":{"success":true}}')
    stub_request(:delete, "#{BASE_URL}/api/v1/projects/p_1/secrets/STRIPE_KEY")
      .to_return(status: 200, body: '{"data":{"success":true}}')

    c = make_client
    list = c.secrets.list("p_1")
    assert_equal 2, list.length
    assert_equal "STRIPE_KEY", list.first["name"]
    c.secrets.set("p_1", "STRIPE_KEY", "sk_xxx")
    c.secrets.remove("p_1", "STRIPE_KEY")
  end

  # ── library ───────────────────────────────────────────────────────

  def test_library_list_bare_array
    stub_request(:get, "#{BASE_URL}/api/v1/library")
      .to_return(status: 200, body: '{"data":[{"id":"p_1","name":"Cat","cloneCount":42}]}')
    out = make_client.library.list
    assert_equal 1, out.length
    assert_equal 42, out.first["cloneCount"]
  end

  def test_library_list_items_envelope
    stub_request(:get, "#{BASE_URL}/api/v1/library")
      .to_return(status: 200, body: '{"data":{"items":[{"id":"p_2","name":"RSI"}]}}')
    out = make_client.library.list
    assert_equal "p_2", out.first["id"]
  end

  def test_library_clone
    stub_request(:post, "#{BASE_URL}/api/v1/library/p_1/clone")
      .with(body: hash_including("subdomain" => "my-cafe"))
      .to_return(status: 200, body: '{"data":{"id":"p_new","subdomain":"my-cafe","status":"queued"}}')
    out = make_client.library.clone("p_1", subdomain: "my-cafe")
    assert_equal "p_new", out["id"]
  end

  # ── usage ─────────────────────────────────────────────────────────

  def test_usage_summary
    stub_request(:get, "#{BASE_URL}/api/v1/usage/summary")
      .to_return(status: 200, body: '{"data":{"plan":{"name":"business","monthlyCredits":10000},"credits":{"currentCredits":5000},"currentPeriod":{"buildsUsed":12}}}')
    out = make_client.usage.summary
    assert_equal "business", out["plan"]["name"]
    assert_equal 12, out["currentPeriod"]["buildsUsed"]
  end

  # ── subscriptions ────────────────────────────────────────────────

  def test_subscriptions_current_populated
    stub_request(:get, "#{BASE_URL}/api/v1/subscriptions/current")
      .to_return(
        status: 200,
        body: '{"data":{"subscription":{"status":"active","billingPeriod":"monthly","currentPeriodStart":"2026-04-01T00:00:00Z","currentPeriodEnd":"2026-05-01T00:00:00Z","canceledAt":null,"planName":"pro","planDisplayName":"Pro","priceMonthly":29,"priceAnnual":290,"monthlyCredits":500,"maxProjects":50,"maxStorageMb":5000,"maxBandwidthMb":50000,"creditRolloverMonths":1,"features":{"teams":true}},"credits":{"current":423,"rolledOver":50,"total":473,"rolloverExpiresAt":"2026-05-01T00:00:00Z","lifetimeUsed":1234}}}',
      )
    out = make_client.subscriptions.current
    assert_equal "pro", out["subscription"]["planName"]
    assert_equal 500, out["subscription"]["monthlyCredits"]
    assert_equal 473, out["credits"]["total"]
  end

  def test_subscriptions_current_both_null
    stub_request(:get, "#{BASE_URL}/api/v1/subscriptions/current")
      .to_return(status: 200, body: '{"data":{"subscription":null,"credits":null}}')
    out = make_client.subscriptions.current
    assert_nil out["subscription"]
    assert_nil out["credits"]
  end

  # ── api_keys ──────────────────────────────────────────────────────

  def test_api_keys_list_create_remove_by_name
    stub_request(:get, "#{BASE_URL}/api/v1/api-keys")
      .to_return(status: 200, body: '{"data":{"keys":[{"id":"k_7","name":"my-script","keyPrefix":"flp_"}]}}')
    stub_request(:post, "#{BASE_URL}/api/v1/api-keys")
      .with(body: hash_including("name" => "new"))
      .to_return(status: 200, body: '{"data":{"id":"k_new","rawKey":"flp_secretsecret","keyPrefix":"flp_secre"}}')
    stub_request(:delete, "#{BASE_URL}/api/v1/api-keys/k_7")
      .to_return(status: 200, body: '{"data":{"success":true}}')

    c = make_client
    list = c.api_keys.list
    assert_equal 1, list.length

    issued = c.api_keys.create(name: "new")
    assert_equal "flp_secretsecret", issued["rawKey"]

    c.api_keys.remove("my-script") # by name

    err = assert_raises(FloopFloop::Error) { c.api_keys.remove("ghost") }
    assert_equal "NOT_FOUND", err.code
  end

  # ── uploads ───────────────────────────────────────────────────────

  def test_uploads_happy_path
    # The S3 URL the presign returns happens to resolve against our
    # WebMock loopback too.
    s3_url = "#{BASE_URL}/s3/put"
    stub_request(:post, "#{BASE_URL}/api/v1/uploads")
      .with(body: hash_including("fileName" => "cat.png", "fileType" => "image/png"))
      .to_return(status: 200, body: %({"data":{"uploadUrl":"#{s3_url}","key":"uploads/u_1/cat.png","fileId":"f_1"}}))
    stub_request(:put, s3_url).to_return(status: 200)

    out = make_client.uploads.create(
      file_name: "cat.png",
      bytes: "fake-png-bytes".b,
    )
    assert_equal "uploads/u_1/cat.png", out["key"]
    assert_equal "image/png", out["fileType"]
    assert_equal 14, out["fileSize"]
  end

  def test_uploads_rejects_unknown_ext
    err = assert_raises(FloopFloop::Error) do
      make_client.uploads.create(file_name: "archive.tar.gz", bytes: "x")
    end
    assert_equal "VALIDATION_ERROR", err.code
  end

  def test_uploads_rejects_oversize
    big = "x" * (FloopFloop::Uploads::MAX_UPLOAD_BYTES + 1)
    err = assert_raises(FloopFloop::Error) do
      make_client.uploads.create(file_name: "big.png", bytes: big)
    end
    assert_equal "VALIDATION_ERROR", err.code
    assert_includes err.message, "upload limit"
  end

  def test_uploads_create_from_path
    s3_url = "#{BASE_URL}/s3/put"
    stub_request(:post, "#{BASE_URL}/api/v1/uploads")
      .to_return(status: 200, body: %({"data":{"uploadUrl":"#{s3_url}","key":"uploads/k","fileId":"f"}}))
    stub_request(:put, s3_url).to_return(status: 200)

    require "tempfile"
    Tempfile.open(%w[cat_ .png]) do |tf|
      tf.binmode
      tf.write("png-bytes")
      tf.flush
      out = make_client.uploads.create_from_path(tf.path)
      assert_equal "png-bytes".bytesize, out["fileSize"]
      assert_equal "image/png", out["fileType"]
    end
  end

  def test_guess_mime_type
    assert_equal "image/png", FloopFloop::Uploads.guess_mime_type("cat.PNG")
    assert_equal "application/pdf", FloopFloop::Uploads.guess_mime_type("doc.pdf")
    assert_nil FloopFloop::Uploads.guess_mime_type("archive.tar.gz")
    assert_nil FloopFloop::Uploads.guess_mime_type("noext")
  end
end
