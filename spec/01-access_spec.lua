local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"

for _ , strategy in helpers.each_strategy() do
  local introspection_url = string.format("http://%s/introspect" ,
    helpers.test_conf.proxy_listen[1])

  describe("Plugin: basic-auth (access)" , function()
    local client , admin_client
    setup(function()
      local dao = select(3 , helpers.get_db_utils(strategy))

      assert(dao.apis:insert {
        name = "introspection-api",
        uris = { "/introspect" },
        upstream_url = "http://mockbin.com"
      })

      local api1 = assert(dao.apis:insert {
        name = "api-1",
        hosts = { "introspection.com" },
        upstream_url = "http://mockbin.com"
      })
      assert(dao.plugins:insert {
        name = "oauth2-introspection",
        api_id = api1.id,
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          ttl = 1
        }
      })

      local api2 = assert(dao.apis:insert {
        name = "api-2",
        hosts = { "introspection2.com" },
        upstream_url = "http://mockbin.com"
      })
      assert(dao.plugins:insert {
        name = "oauth2-introspection",
        api_id = api2.id,
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          hide_credentials = true
        }
      })

      assert(dao.consumers:insert {
        username = "bob"
      })
      local consumer = assert(dao.consumers:insert {
        username = "limited-bob"
      })
      assert(dao.plugins:insert {
        name = "correlation-id",
        api_id = api1.id,
        consumer_id = consumer.id,
        config = {},
      })

      local anonymous_user = assert(dao.consumers:insert {
        username = "no-body",
      })

      local api3 = assert(dao.apis:insert {
        name = "api-3",
        hosts = { "introspection3.com" },
        upstream_url = "http://mockbin.com"
      })
      assert(dao.plugins:insert {
        name = "oauth2-introspection",
        api_id = api3.id,
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          ttl = 1,
          anonymous = anonymous_user.id,
        }
      })

      local api4 = assert(dao.apis:insert {
        name = "api-4",
        hosts = { "introspection4.com" },
        upstream_url = "http://mockbin.com"
      })
      assert(dao.plugins:insert {
        name = "oauth2-introspection",
        api_id = api4.id,
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          ttl = 1,
          anonymous = utils.uuid(),
        }
      })

      local api5 = assert(dao.apis:insert {
        name = "api-5",
        hosts = { "introspection5.com" },
        upstream_url = "http://mockbin.com"
      })
      assert(dao.plugins:insert {
        name = "oauth2-introspection",
        api_id = api5.id,
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          ttl = 1,
          run_on_preflight = false
        }
      })

      assert(helpers.start_kong({
        database = strategy,
        custom_plugins = "introspection-endpoint, oauth2-introspection",
        lua_package_path = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua;/kong-plugin/spec/fixtures/custom_plugins/?.lua;;"
      }))

      client = helpers.proxy_client()
      admin_client = helpers.admin_client()

      local res = assert(admin_client:send {
        method = "POST",
        path = "/apis/introspection-api/plugins/",
        body = {
          name = "introspection-endpoint"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(201 , res)
    end)
    teardown(function()
      if admin_client then
        admin_client:close()
      end
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    describe("Introspection Endpoint Mock" , function()
      it("validates valid token" , function()
        local res = assert(client:send {
          method = "POST",
          path = "/introspect",
          body = ngx.encode_args({ token = "valid" }),
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
          }
        })

        local body = assert.res_status(200 , res)
        assert.equal([[{"active":true}]] , body)
      end)

      it("does not validate invalid token" , function()
        local res = assert(client:send {
          method = "POST",
          path = "/introspect",
          body = ngx.encode_args({ token = "invalid" }),
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
          }
        })

        local body = assert.res_status(200 , res)
        assert.equal([[{"active":false}]] , body)
      end)
    end)

    describe("Unauthorized" , function()
      it("missing access_token" , function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "introspection.com"
          }
        })

        local body = assert.res_status(401 , res)
        local json = cjson.decode(body)
        assert.equal("invalid_request" , json.error)
        assert.equal("The access token is missing" , json.error_description)
      end)
      it("invalid access_token" , function()
        local res = assert(client:send {
          method = "GET",
          path = "/request?access_token=asd",
          headers = {
            ["Host"] = "introspection.com"
          }
        })

        local body = assert.res_status(401 , res)
        local json = cjson.decode(body)
        assert.equal("invalid_token" , json.error)
        assert.equal("The access token is invalid or has expired" , json.error_description)
      end)
    end)

    describe("Authorized" , function()
      it("validates a token in the querystring" , function()
        local res = assert(client:send {
          method = "GET",
          path = "/request?access_token=valid",
          headers = {
            ["Host"] = "introspection.com"
          }
        })

        assert.res_status(200 , res)
      end)
      it("validates a token in the body" , function()
        local res = assert(client:send {
          method = "POST",
          path = "/request",
          body = ngx.encode_args({ access_token = "valid" }),
          headers = {
            ["Host"] = "introspection.com",
            ["Content-Type"] = "application/x-www-form-urlencoded"
          }
        })

        assert.res_status(200 , res)
      end)
      it("validates a token in the header" , function()
        local res = assert(client:send {
          method = "POST",
          path = "/request",
          headers = {
            ["Host"] = "introspection.com",
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Authorization"] = "Bearer valid"
          }
        })

        local body = cjson.decode(assert.res_status(200 , res))
        assert.is_nil(body.headers["x-consumer-username"])
      end)

      describe("Consumer" , function()
        it("associates a consumer" , function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_consumer",
            headers = {
              ["Host"] = "introspection.com"
            }
          })

          local body = cjson.decode(assert.res_status(200 , res))
          assert.equal("bob" , body.headers["x-consumer-username"])
          assert.is_string(body.headers["x-consumer-id"])
          assert.is_nil(res.headers["x-ratelimit-limit-minute"])
        end)
        it("invokes other consumer-specific plugins" , function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_consumer_limited",
            headers = {
              ["Host"] = "introspection.com"
            }
          })

          local body = cjson.decode(assert.res_status(200 , res))
          assert.equal("limited-bob" , body.headers["x-consumer-username"])
          assert.is_string(body.headers["kong-request-id"])
        end)
      end)

      describe("upstream headers" , function()
        it("appends upstream headers" , function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_complex",
            headers = {
              ["Host"] = "introspection.com"
            }
          })

          local body = cjson.decode(assert.res_status(200 , res))
          assert.equal("valid_complex" , body.queryString.access_token)
          assert.equal("some_client_id" , body.headers["x-credential-client-id"])
          assert.equal("some_username" , body.headers["x-credential-username"])
          assert.equal("some_scope" , body.headers["x-credential-scope"])
          assert.equal("some_sub" , body.headers["x-credential-sub"])
          assert.equal("some_aud" , body.headers["x-credential-aud"])
          assert.equal("some_iss" , body.headers["x-credential-iss"])
          assert.equal("some_exp" , body.headers["x-credential-exp"])
          assert.equal("some_iat" , body.headers["x-credential-iat"])
        end)
      end)
      describe("hide credentials" , function()
        it("appends upstream headers" , function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_complex&hello=marco",
            headers = {
              ["Host"] = "introspection2.com"
            }
          })

          local body = cjson.decode(assert.res_status(200 , res))
          assert.is_nil(body.queryString.access_token)
          assert.equal("some_client_id" , body.headers["x-credential-client-id"])
          assert.equal("some_username" , body.headers["x-credential-username"])
          assert.equal("some_scope" , body.headers["x-credential-scope"])
          assert.equal("some_sub" , body.headers["x-credential-sub"])
          assert.equal("some_aud" , body.headers["x-credential-aud"])
          assert.equal("some_iss" , body.headers["x-credential-iss"])
          assert.equal("some_exp" , body.headers["x-credential-exp"])
          assert.equal("some_iat" , body.headers["x-credential-iat"])
        end)
      end)

      describe("auth with preflight and OPTIONS method" , function()
        it("should be unauthorized" , function()
          local res = assert(client:send {
            method = "OPTIONS",
            path = "/request",
            headers = {
              ["Host"] = "introspection.com"
            }
          })

          assert.res_status(401 , res)
        end)
        it("should overrride auth" , function()
          local res = assert(client:send {
            method = "OPTIONS",
            path = "/request",
            headers = {
              ["Host"] = "introspection5.com"
            }
          })

          assert.res_status(200 , res)
        end)
      end)

      describe("config.anonymous" , function()
        it("works with right credentials and anonymous" , function()
          local res = assert(client:send {
            method = "POST",
            path = "/request?access_token=valid_consumer",
            headers = {
              ["Host"] = "introspection3.com"
            }
          })
          local body = cjson.decode(assert.res_status(200 , res))
          assert.equal('bob' , body.headers["x-consumer-username"])
          assert.is_nil(body.headers["x-anonymous-consumer"])
        end)
        it("works with wrong credentials and anonymous" , function()
          local res = assert(client:send {
            method = "POST",
            path = "/request",
            headers = {
              ["Host"] = "introspection3.com"
            }
          })
          local body = cjson.decode(assert.res_status(200 , res))
          assert.equal('true' , body.headers["x-anonymous-consumer"])
          assert.equal('no-body' , body.headers["x-consumer-username"])
        end)
        it("errors when anonymous user doesn't exist" , function()
          local res = assert(client:send {
            method = "GET",
            path = "/request",
            headers = {
              ["Host"] = "introspection4.com"
            }
          })
          assert.response(res).has.status(500)
        end)
      end)
    end)
  end)

  describe("multiple auth" , function()

    local client , user1 , user2 , anonymous , admin_client

    setup(function()
      local dao = select(3 , helpers.get_db_utils(strategy))

      assert(dao.apis:insert {
        name = "introspection-api",
        uris = { "/introspect" },
        upstream_url = "http://mockbin.com"
      })
      local api1 = assert(dao.apis:insert {
        name = "api-1",
        hosts = { "logical-and.com" },
        upstream_url = "http://mockbin.com",
      })
      assert(dao.plugins:insert {
        name = "key-auth",
        api_id = api1.id,
      })
      assert(dao.plugins:insert {
        name = "oauth2-introspection",
        api_id = api1.id,
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          ttl = 1
        }
      })

      anonymous = assert(dao.consumers:insert {
        username = "Anonymous",
      })
      user1 = assert(dao.consumers:insert {
        username = "bob",
      })
      user2 = assert(dao.consumers:insert {
        username = "alice",
      })
      assert(dao.keyauth_credentials:insert {
        key = "mouse",
        consumer_id = user2.id,
      })

      local api2 = assert(dao.apis:insert {
        name = "api-2",
        hosts = { "logical-or.com" },
        upstream_url = "http://mockbin.com",
      })
      assert(dao.plugins:insert {
        name = "oauth2-introspection",
        api_id = api2.id,
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          ttl = 1,
          anonymous = anonymous.id,
        }
      })

      assert(dao.plugins:insert {
        name = "key-auth",
        api_id = api2.id,
        config = {
          anonymous = anonymous.id,
        },
      })

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        custom_plugins = "introspection-endpoint, oauth2-introspection",
        lua_package_path = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua;/kong-plugin/spec/fixtures/custom_plugins/?.lua;;",
      }))

      client = helpers.proxy_client()
      admin_client = helpers.admin_client()

      local res = assert(admin_client:send {
        method = "POST",
        path = "/apis/introspection-api/plugins/",
        body = {
          name = "introspection-endpoint"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(201 , res)
    end)

    teardown(function()
      if client then
        client:close()
      end
      if admin_client then
        admin_client:close()
      end
      helpers.stop_kong()
    end)

    describe("multiple auth without anonymous, logical AND" , function()

      it("passes with all credentials provided" , function()
        local res = assert(client:send {
          method = "GET",
          path = "/request?access_token=valid",
          headers = {
            ["Host"] = "logical-and.com",
            ["apikey"] = "mouse",
          }
        })
        local body = cjson.decode(assert.res_status(200 , res))
        assert.is_nil(body.headers["x-anonymous-consumer"])
        local id = body.headers["x-consumer-id"]
        assert.not_equal(id , anonymous.id)
        assert(id == user1.id or id == user2.id)
      end)

      it("fails 401, with only the first credential provided" , function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "logical-and.com",
            ["apikey"] = "mouse",
          }
        })
        assert.res_status(401 , res)
      end)

      it("fails 401, with only the second credential provided" , function()
        local res = assert(client:send {
          method = "GET",
          path = "/request?access_token=valid",
          headers = {
            ["Host"] = "logical-and.com"
          }
        })
        assert.res_status(401 , res)
      end)

      it("fails 401, with no credential provided" , function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "logical-and.com",
          }
        })
        assert.res_status(401 , res)
      end)
    end)

    describe("multiple auth with anonymous, logical OR" , function()
      it("passes with all credentials provided" , function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "logical-or.com",
            ["apikey"] = "mouse",
          }
        })

        local body = cjson.decode(assert.res_status(200 , res))
        assert.is_nil(body.headers["x-anonymous-consumer"])
        local id = body.headers["x-consumer-id"]
        assert.not_equal(id , anonymous.id)
        assert(id == user1.id or id == user2.id)
      end)

      it("passes with only the first credential provided" , function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "logical-or.com",
            ["apikey"] = "mouse",
          }
        })

        local body = cjson.decode(assert.res_status(200 , res))
        assert.is_nil(body.headers["x-anonymous-consumer"])
        local id = body.headers["x-consumer-id"]
        assert.not_equal(id , anonymous.id)
        assert.equal(user2.id , id)
      end)

      it("passes with only the second credential provided" , function()
        local res = assert(client:send {
          method = "GET",
          path = "/request?access_token=valid_consumer",
          headers = {
            ["Host"] = "logical-or.com",
          }
        })
        local body = cjson.decode(assert.res_status(200 , res))
        assert.is_nil(body.headers["x-anonymous-consumer"])
        local id = body.headers["x-consumer-id"]
        assert.not_equal(id , anonymous.id)
        assert.equal(user1.id , id)
      end)

      it("passes with no credential provided" , function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "logical-or.com",
          }
        })
        local body = cjson.decode(assert.res_status(200 , res))
        assert.not_nil(body.headers["x-anonymous-consumer"])
        local id = body.headers["x-consumer-id"]
        assert.equal(id , anonymous.id)
      end)
    end)
  end)
end

