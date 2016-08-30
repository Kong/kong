local helpers = require "spec.helpers"
local cjson = require "cjson"
local meta = require "kong.meta"

describe("Resolver", function()
  local client
  setup(function()
    assert(helpers.start_kong())
    client = helpers.proxy_client()

    -- request_host
    assert(helpers.dao.apis:insert {
      request_host = "mockbin.com",
      upstream_url = "http://mockbin.com"
    })
    -- wildcard
    assert(helpers.dao.apis:insert {
      request_host = "*.wildcard.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.apis:insert {
      request_host = "wildcard.*",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.apis:insert {
      request_host = "*.my-test.wildcard.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.apis:insert {
      request_host = "*.my-test.another-wildcard.com",
      upstream_url = "http://mockbin.com"
    })
    -- request_path
    assert(helpers.dao.apis:insert {
      request_path = "/status/200",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.apis:insert {
      request_path = "/status/301",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.apis:insert {
      request_path = "/request",
      upstream_url = "http://mockbin.com"
    })
    -- strip_request_path
    assert(helpers.dao.apis:insert {
      request_path = "/mockbin",
      upstream_url = "http://mockbin.com",
      strip_request_path = true
    })
    assert(helpers.dao.apis:insert {
      request_path = "/mockbin-with-hyphens",
      upstream_url = "http://mockbin.com",
      strip_request_path = true
    })
    assert(helpers.dao.apis:insert {
      request_path = "/status/201",
      upstream_url = "http://mockbin.com",
      strip_request_path = true
    })
    assert(helpers.dao.apis:insert {
      request_path = "/request/request",
      upstream_url = "http://mockbin.com",
      strip_request_path = true
    })
    assert(helpers.dao.apis:insert {
      request_path = "/status/204",
      upstream_url = "http://mockbin.com/status/204",
      strip_request_path = true
    })
    assert(helpers.dao.apis:insert {
      request_path = "/request/urlenc/%20%20",
      upstream_url = "http://mockbin.com/",
    })
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  it("404 if can't find API to proxy", function()
    -- by host`
    local res = assert(client:send {
      method = "GET",
      headers = {
        ["Host"] = "inexistent.com"
      }
    })
    local body = assert.res_status(404, res)
    assert.is_nil(res.headers.via)
    assert.equal([[{"request_path":"\/","message":"API not found with these values",]]
               ..[["request_host":["inexistent.com"]}]], body)

    res = assert(client:send {
      method = "GET",
      path = "/inexistent"
    })
    body = assert.res_status(404, res)
    assert.is_nil(res.headers.via)
    assert.equal([[{"request_path":"\/inexistent","message":"API not found with these values",]]
               ..[["request_host":["0.0.0.0"]}]], body)
  end)

  describe("proxying by request_host", function()
    setup(function()

    end)
    it("sanity", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "mockbin.com"
        }
      })
      assert.res_status(200, res)
      assert.equal(meta._NAME.."/"..meta._VERSION, res.headers.via)
      assert.not_matches("kong", res.headers.server)
    end)
    it("Host formats", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "  mockbin.com "
        }
      })
      assert.res_status(200, res)
    end)
    it("Host with port", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "mockbin.com:80"
        }
      })
      assert.res_status(200, res)
    end)
    it("X-Host-Override (legacy)", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "example.com",
          ["X-Host-Override"] = "mockbin.com"
        }
      })
      assert.res_status(200, res)
    end)
    describe("wildcard request_host", function()
      it("subdomain", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "subdomain.wildcard.com"
          }
        })
        assert.res_status(200, res)
      end)
      it("subdomain with dash", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "host.my-test.wildcard.com"
          }
        })
        assert.res_status(200, res)
      end)
      it("another subdomain with dash", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "host.my-test.another-wildcard.com"
          }
        })
        assert.res_status(200, res)
      end)
      it("TLD", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "wildcard.org"
          }
        })
        assert.res_status(200, res)
      end)
    end)
  end)

  describe("proxying by request_path", function()
    it("sanity", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200"
      })
      assert.res_status(200, res)
      assert.equal(meta._NAME.."/"..meta._VERSION, res.headers.via)
      assert.not_matches("kong", res.headers.server)

      res = assert(client:send {
        method = "GET",
        path = "/status/301"
      })
      assert.res_status(301, res)
    end)
    it("only proxies when the full request_path matches", function()
      local res = assert(client:send {
        method = "GET",
        path = "/somerequest_path/status/200"
      })
      local body = assert.res_status(404, res)
      assert.equal([[{"request_path":"\/somerequest_path\/status\/200","message":"API not found]]
                 ..[[ with these values","request_host":["0.0.0.0"]}]], body)
    end)
    it("disregards querystrings", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200/?foo=bar&hello=world"
      })
      assert.res_status(200, res)
    end)
    it("doesn't append trailing slash when strip_request_path is false", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("http://mockbin.com/request", json.url)
    end)
    it("proxies percent-encoded request_path", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request/urlenc/%20%20"
      })
      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.equals("http://mockbin.com/request/urlenc/%20%20", json.url)
    end)

    describe("strip_request_path", function()
      it("sanity", function()
        local res = assert(client:send {
          method = "GET",
          path = "/mockbin/request"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("http://mockbin.com/request", json.url)
      end)
      it("request_path contains pattern characters", function()
        local res = assert(client:send {
          method = "GET",
          path = "/mockbin-with-hyphens/request"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("http://mockbin.com/request", json.url)
      end)
      it("preserves querystring", function()
        local res = assert(client:send {
          method = "GET",
          path = "/mockbin/request?hello=world"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("http://mockbin.com/request?hello=world", json.url)
      end)
      it("only strips the first occurrence of request_path in URI", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request/request/request"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("http://mockbin.com/request", json.url)
      end)
      it("doesn't strip occurrences in the upstream_url", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/204"
        })
        assert.res_status(204, res)
      end)
      it("maintains trailing slash if request URI has one", function()
        local res = assert(client:send {
          method = "GET",
          path = "/mockbin/request/"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("http://mockbin.com/request/", json.url)
      end)
    end)
  end)

  describe("percent-encoding", function()
    it("preserves percent-encoded values in URI", function()
      local res = assert(client:send {
        method = "GET",
        path = "/mockbin/request?hello%20bonjour=world%2funiverse"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("http://mockbin.com/request?hello%20bonjour=world%2funiverse", json.url)
    end)
  end)

  it("timing headers", function()
    local res = assert(client:send {
      method = "GET",
      path = "/status/200"
    })
    assert.res_status(200, res)
    assert.is_string(res.headers["x-kong-proxy-latency"])
    assert.is_string(res.headers["x-kong-upstream-latency"])
  end)

  describe("SSL", function()
    local ssl_client
    setup(function()
      ssl_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_ssl_port))
      assert(ssl_client:ssl_handshake(false))
    end)
    teardown(function()
      if ssl_client then ssl_client:close() end
    end)
    it("listens on SSL port", function()
      local res = assert(ssl_client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "mockbin.com"
        }
      })
      assert.res_status(200, res)
    end)
  end)

  it("returns 414 when the URI is too long", function()
    local querystring = ""
    for i=1,5000 do
      querystring = string.format("%s%s_%d=%d&", querystring, "param", i, i)
    end

    local res = assert(client:send {
      method = "GET",
      path = "/status/200?"..querystring,
      headers = {
        ["Host"] = "mockbin.com"
      }
    })
    assert.res_status(414, res)
  end)
end)
