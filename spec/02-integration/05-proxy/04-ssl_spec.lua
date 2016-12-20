local ssl_fixtures = require "spec.03-plugins.16-ssl.fixtures"
local helpers = require "spec.helpers"


local function get_cert(server_name)
  local _, _, stdout = assert(helpers.execute(
    string.format("echo 'GET /' | openssl s_client -connect 0.0.0.0:%d -servername %s",
                  helpers.test_conf.proxy_ssl_port, server_name)
  ))

  return stdout
end


describe("SSL", function()
  local client, client_ssl, admin_client

  setup(function()
    assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "example.com", "ssl1.com" },
      upstream_url = "http://httpbin.org",
    })

    assert(helpers.start_kong())

    client = helpers.proxy_client()
    admin_client = helpers.admin_client()

    assert(admin_client:send {
      method = "POST",
      path = "/certificates",
      body = {
        cert = ssl_fixtures.cert,
        key  = ssl_fixtures.key,
        snis = "example.com,ssl1.com",
      },
      headers = { ["Content-Type"] = "application/json" },
    })
  end)

  teardown(function()
    helpers.stop_kong(nil, true)
  end)

  describe("handshake", function()
    it("sets the default fallback SSL certificate if no SNI match", function()
      local cert = get_cert("test.com")
      assert.matches("CN=localhost", cert, nil, true)
    end)

    it("sets the configured SSL certificate if SNI match", function()
      local cert = get_cert("ssl1.com")
      assert.matches("CN=ssl1.com", cert, nil, true)

      cert = get_cert("example.com")
      assert.matches("CN=ssl1.com", cert, nil, true)
    end)
  end)

  describe("https_only", function()

  end)

  describe("SSL certificates and SNIs invalidations", function()

  end)
end)
