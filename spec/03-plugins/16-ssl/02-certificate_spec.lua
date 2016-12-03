local ssl_fixtures = require "spec.03-plugins.16-ssl.fixtures"
local helpers = require "spec.helpers"

local function get_cert(server_name)
  local _, _, stdout = assert(helpers.execute(
    string.format("echo 'GET /' | openssl s_client -connect 0.0.0.0:%d -servername %s",
                  helpers.test_conf.proxy_ssl_port, server_name)
  ))
  return stdout
end

describe("Plugin: ssl (certificate)", function()
  setup(function()
    local api = assert(helpers.dao.apis:insert {
      name = "ssl1_com",
      hosts = { "ssl1.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ssl",
      api_id = api.id,
      config = {
        cert = ssl_fixtures.cert,
        key = ssl_fixtures.key
      }
    })

    api = assert(helpers.dao.apis:insert {
      name = "api-2",
      hosts = { "ssl2.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ssl",
      api_id = api.id,
      config = {
        only_https = true,
        key = ssl_fixtures.key,
        cert = ssl_fixtures.cert
      }
    })

    api = assert(helpers.dao.apis:insert {
      name = "api-4",
      hosts = { "ssl4.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ssl",
      api_id = api.id,
      config = {
        only_https = true,
        key = ssl_fixtures.key,
        cert = ssl_fixtures.cert,
        accept_http_if_already_terminated = true
      }
    })

    assert(helpers.start_kong {
      ssl_cert = "", -- trigger cert auto-gen
      ssl_cert_key = ""
    })
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("returns default cert when requesting other APIs", function()
    local cert = get_cert("test.com")
    assert.matches("US/ST=California/L=San Francisco/O=Kong/OU=IT Department/CN=localhost", cert, nil, true)
  end)
  it("returns configured cert when requesting API", function()
    local cert = get_cert("ssl1.com")
    assert.matches("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com", cert, nil, true)
  end)
  it("can upload SSL cert with curl multipart", function()
    local api = assert(helpers.dao.apis:insert {
      name = "api-3",
      hosts = { "ssl3.com" },
      upstream_url = "http://mockbin.com"
    })

    local _, _, stdout = assert(helpers.execute(
      string.format([[curl -s -o /dev/null -w "%%{http_code}" http://%s/apis/%s/plugins/ \
                      --form "name=ssl" \
                      --form "config.cert=@%s" \
                      --form "config.key=@%s"]],
        helpers.test_conf.admin_listen,
        api.id,
        helpers.test_conf.ssl_cert_default,
        helpers.test_conf.ssl_cert_key_default)
    ))

    assert.equal(201, tonumber(stdout))
  end)
end)
