local helpers = require "spec.helpers"
local cjson = require "cjson"
local cache = require "kong.tools.database_cache"

describe("Plugin: ACL (access)", function()
  local client, api_client
  setup(function()
    assert(helpers.start_kong())

    local consumer1 = assert(helpers.dao.consumers:insert {
      username = "consumer1"
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "apikey123",
      consumer_id = consumer1.id
    })

    local consumer2 = assert(helpers.dao.consumers:insert {
      username = "consumer2"
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "apikey124",
      consumer_id = consumer2.id
    })
    assert(helpers.dao.acls:insert {
      group = "admin",
      consumer_id = consumer2.id
    })

    local consumer3 = assert(helpers.dao.consumers:insert {
      username = "consumer3"
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "apikey125",
      consumer_id = consumer3.id
    })
    assert(helpers.dao.acls:insert {
      group = "pro",
      consumer_id = consumer3.id
    })
    assert(helpers.dao.acls:insert {
      group = "hello",
      consumer_id = consumer3.id
    })

    local consumer4 = assert(helpers.dao.consumers:insert {
      username = "consumer4"
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "apikey126",
      consumer_id = consumer4.id
    })
    assert(helpers.dao.acls:insert {
      group = "free",
      consumer_id = consumer4.id
    })
    assert(helpers.dao.acls:insert {
      group = "hello",
      consumer_id = consumer4.id
    })

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "acl1.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "acl",
      api_id = api1.id,
      config = {
        whitelist = "admin"
      }
    })

    local api2 = assert(helpers.dao.apis:insert {
      request_host = "acl2.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "acl",
      api_id = api2.id,
      config = {
        whitelist = "admin"
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api2.id,
      config = {}
    })

    local api3 = assert(helpers.dao.apis:insert {
      request_host = "acl3.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "acl",
      api_id = api3.id,
      config = {
        blacklist = {"admin"}
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api3.id,
      config = {}
    })

    local api4 = assert(helpers.dao.apis:insert {
      request_host = "acl4.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "acl",
      api_id = api4.id,
      config = {
        whitelist = {"admin", "pro"}
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api4.id,
      config = {}
    })

    local api5 = assert(helpers.dao.apis:insert {
      request_host = "acl5.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "acl",
      api_id = api5.id,
      config = {
        blacklist = {"admin", "pro"}
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api5.id,
      config = {}
    })

    local api6 = assert(helpers.dao.apis:insert {
      request_host = "acl6.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "acl",
      api_id = api6.id,
      config = {
        blacklist = {"admin", "pro", "hello"}
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api6.id,
      config = {}
    })

    local api7 = assert(helpers.dao.apis:insert {
      request_host = "acl7.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "acl",
      api_id = api7.id,
      config = {
        whitelist = {"admin", "pro", "hello"}
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api7.id,
      config = {}
    })
  end)
  before_each(function()
    client = helpers.proxy_client()
    api_client = helpers.admin_client()
  end)
  after_each(function ()
    client:close()
    api_client:close()
  end)
  teardown(function()
    helpers.stop_kong()
  end)

  describe("Simple lists", function()
    it("should fail when an authentication plugin is missing", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "acl1.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"Cannot identify the consumer, add an authentication plugin to use the ACL plugin"}]], body)
    end)

    it("should fail when not in whitelist", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200?apikey=apikey123",
        headers = {
          ["Host"] = "acl2.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"You cannot consume this service"}]], body)
    end)

    it("should work when in whitelist", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?apikey=apikey124",
        headers = {
          ["Host"] = "acl2.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal("admin", body.headers["x-consumer-groups"])
    end)

    it("should work when not in blacklist", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?apikey=apikey123",
        headers = {
          ["Host"] = "acl3.com"
        }
      })
      assert.res_status(200, res)
    end)

    it("should fail when in blacklist", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?apikey=apikey124",
        headers = {
          ["Host"] = "acl3.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"You cannot consume this service"}]], body)
    end)
  end)

  describe("Multi lists", function()
    it("should work when in whitelist", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?apikey=apikey125",
        headers = {
          ["Host"] = "acl4.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.True(body.headers["x-consumer-groups"] == "pro, hello" or body.headers["x-consumer-groups"] == "hello, pro")
    end)

    it("should fail when not in whitelist", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?apikey=apikey126",
        headers = {
          ["Host"] = "acl4.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"You cannot consume this service"}]], body)
    end)

    it("should fail when in blacklist", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?apikey=apikey125",
        headers = {
          ["Host"] = "acl5.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"You cannot consume this service"}]], body)
    end)

    it("should work when not in blacklist", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?apikey=apikey126",
        headers = {
          ["Host"] = "acl5.com"
        }
      })
      assert.res_status(200, res)
    end)

    it("should not work when one of the ACLs in the blacklist", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?apikey=apikey126",
        headers = {
          ["Host"] = "acl6.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"You cannot consume this service"}]], body)
    end)

    it("should work when one of the ACLs in the whitelist", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?apikey=apikey126",
        headers = {
          ["Host"] = "acl7.com"
        }
      })
      assert.res_status(200, res)
    end)

    it("should not work when at least one of the ACLs in the blacklist", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?apikey=apikey125",
        headers = {
          ["Host"] = "acl6.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"You cannot consume this service"}]], body)
    end)
  end)

  describe("Real-world usage", function()
    it("should not fail when multiple rules are set fast", function()
      -- Create consumer
      local res = assert(api_client:send {
        method = "POST",
        path = "/consumers/",
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          username = "acl_consumer"
        }
      })
      local body = cjson.decode(assert.res_status(201, res))
      local consumer_id = body.id

      -- Create key
      local res = assert(api_client:send {
        method = "POST",
        path = "/consumers/acl_consumer/key-auth/",
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          key = "secret123"
        }
      })
      assert.res_status(201, res)

      for i = 1, 3 do
        -- Create API
        local res = assert(api_client:send {
          method = "POST",
          path = "/apis/",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            name = "acl_test"..i,
            request_host = "acl_test"..i..".com",
            upstream_url = "http://mockbin.com"
          }
        })
        assert.res_status(201, res)

        -- Add the ACL plugin to the new API with the new group
        local res = assert(api_client:send {
          method = "POST",
          path = "/apis/acl_test"..i.."/plugins/",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            name = "acl",
            ["config.whitelist"] = "admin"..i
          }
        })
        assert.res_status(201, res)

        -- Add key-authentication to API
        local res = assert(api_client:send {
          method = "POST",
          path = "/apis/acl_test"..i.."/plugins/",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            name = "key-auth"
          }
        })
        assert.res_status(201, res)

        -- Add a new group the the consumer
        local res = assert(api_client:send {
          method = "POST",
          path = "/consumers/acl_consumer/acls/",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            group = "admin"..i
          }
        })
        assert.res_status(201, res)

        -- Wait for cache to be invalidated
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/"..cache.acls_key(consumer_id)
          })
          res:read_body()
          return res.status == 404
        end, 5)

        -- Make the request, and it should work

        local res
        helpers.wait_until(function()
          res = assert(client:send {
            method = "GET",
            path = "/status/200?apikey=secret123",
            headers = {
              ["Host"] = "acl_test"..i..".com"
            }
          })
          return res.status ~= 404
        end, 5)

        assert.res_status(200, res)
      end
    end)
  end)
end)
