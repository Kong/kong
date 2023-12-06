-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"


local INTROSPECT_PATH = "/introspect"
local INTROSPECT_IP = "127.0.0.1"
local INTROSPECT_PORT = "10000"
local introspection_url = ("http://%s:%s%s"):format(
                           INTROSPECT_IP, INTROSPECT_PORT, INTROSPECT_PATH)


local fixtures = {
  http_mock = {
    mock_introspection = [=[
      server {
          server_name mock_introspection;
          listen ]=] .. INTROSPECT_PORT .. [=[;
          location ~ "]=] .. INTROSPECT_PATH .. [=[" {
              content_by_lua_block {
                local function x()

                  ngx.req.set_header("Content-Type", "application/json")

                  if ngx.req.get_method() == "POST" then
                    ngx.req.read_body()
                    local args = ngx.req.get_post_args()
                    if not args then
                      return ngx.exit(500)
                    end
                    if args.token == "valid" or
                      args.token == "valid_consumer_client_id" or
                      args.token == "valid_consumer_client_id_not_added_initially" or
                      args.token == "valid_consumer" or
                      args.token == "valid_consumer_limited" or
                      args.token == "valid_complex" then

                      if args.token == "valid_consumer" then
                        ngx.say([[{"active":true,
                                   "username":"bob"}]])
                      elseif args.token == "valid_consumer_client_id" then -- omit `username`, return `client_id`
                        ngx.say([[{"active":true,
                                    "client_id": "kongsumer"}]])
                      elseif args.token == "valid_consumer_client_id_not_added_initially" then -- omit `username`, return `client_id`
                        ngx.say([[{"active":true,
                                    "client_id": "kongsumer_not_added_initially"}]])
                      elseif args.token == "valid_consumer_limited" then
                        ngx.say([[{"active":true,
                                   "username":"limited-bob"}]])
                      elseif args.token == "valid_complex" then
                        ngx.say([[{"active":true,
                                   "username":"some_username",
                                   "client_id":"some_client_id",
                                   "scope":"some_scope",
                                   "sub":"some_sub",
                                   "aud":"some_aud",
                                   "iss":"some_iss",
                                   "exp":"some_exp",
                                   "iat":"some_iat",
                                   "foo":"bar",
                                   "bar":"baz",
                                   "baz":"baaz"}]])
                      else
                        ngx.say([[{"active":true}]])
                      end
                      return ngx.exit(200)
                    end
                  end

                  ngx.say([[{"active":false}]])
                  return ngx.exit(200)

                end
                local ok, err = pcall(x)
                if not ok then
                  ngx.log(ngx.ERR, "Mock error: ", err)
                end
              }
          }
      }
    ]=]
  },
}

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _ , strategy in strategies() do

  describe("Plugin: oauth2-introspection (access) #" .. strategy, function()
    local client , admin_client, introspect_client
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      local bp = helpers.get_db_utils(db_strategy, nil, {"oauth2-introspection"})

      local route1 = bp.routes:insert {
        name = "route-1",
        hosts = { "introspection.test" },
      }
      bp.plugins:insert {
        name = "oauth2-introspection",
        route = { id = route1.id },
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          ttl = 1
        }
      }

      local route1_cid = bp.routes:insert {
        name = "route-1cid",
        hosts = { "introspection_client_id.test" },
      }
      bp.plugins:insert {
        name = "oauth2-introspection",
        route = { id = route1_cid.id },
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          consumer_by = "client_id",
          ttl = 1
        }
      }

      local route2_cid = bp.routes:insert {
        name = "route-2cid",
        hosts = { "introspection_client_id_not_added_initially.test" },
      }
      bp.plugins:insert {
        name = "oauth2-introspection",
        route = { id = route2_cid.id },
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          consumer_by = "client_id"
        }
      }

      local route2 = bp.routes:insert {
        name = "route-2",
        hosts = { "introspection2.test" },
      }
      bp.plugins:insert {
        name = "oauth2-introspection",
        route = { id = route2.id },
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          hide_credentials = true
        }
      }

      bp.consumers:insert {
        username = "bob"
      }
      bp.consumers:insert {
        custom_id = "kongsumer",
      }

      local consumer = bp.consumers:insert {
        username = "limited-bob"
      }
      bp.plugins:insert {
        name = "request-transformer",
        route = { id = route1.id },
        consumer = { id = consumer.id },
        config = {
          add = {
            headers = { "x-another-header:something" }
          }
        },
      }

      local anonymous_user = bp.consumers:insert {
        username = "no-body",
      }

      local route3 = bp.routes:insert {
        name = "route-3",
        hosts = { "introspection3.test" },
      }
      bp.plugins:insert {
        name = "oauth2-introspection",
        route = { id = route3.id },
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          ttl = 1,
          anonymous = anonymous_user.id,
        }
      }

      local route4 = bp.routes:insert {
        name = "route-4",
        hosts = { "introspection4.test" },
      }
      bp.plugins:insert {
        name = "oauth2-introspection",
        route = { id = route4.id },
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          ttl = 1,
          anonymous = utils.uuid(),
        }
      }

      local route5 = bp.routes:insert {
        name = "route-5",
        hosts = { "introspection5.test" },
      }
      bp.plugins:insert {
        name = "oauth2-introspection",
        route = { id = route5.id },
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          ttl = 1,
          run_on_preflight = false
        }
      }

      local route6 = bp.routes:insert {
        name = "route-6",
        hosts = { "introspection6.test" },
      }
      bp.plugins:insert {
        name = "oauth2-introspection",
        route = { id = route6.id },
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          custom_claims_forward = { "foo", "bar" },
          ttl = 1,
        }
      }

      assert(helpers.start_kong({
        database = db_strategy,
        plugins = "bundled,oauth2-introspection",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures))

      client = helpers.proxy_client()
      admin_client = helpers.admin_client()
      introspect_client = helpers.http_client(INTROSPECT_IP, INTROSPECT_PORT, 60000)

    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end
      if client then
        client:close()
      end
      assert(helpers.stop_kong())
    end)

    describe("Introspection Endpoint Mock" , function()
      it("validates valid token" , function()
        local res = assert(introspect_client:send {
          method = "POST",
          path = INTROSPECT_PATH,
          body = ngx.encode_args({ token = "valid" }),
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
          }
        })

        local body = assert.res_status(200 , res)
        assert.equal([[{"active":true}]] , body)
      end)

      it("does not validate invalid token" , function()
        local res = assert(introspect_client:send {
          method = "POST",
          path = INTROSPECT_PATH,
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
            ["Host"] = "introspection.test"
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
            ["Host"] = "introspection.test"
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
            ["Host"] = "introspection.test"
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
            ["Host"] = "introspection.test",
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
            ["Host"] = "introspection.test",
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Authorization"] = "Bearer valid"
          }
        })

        local body = cjson.decode(assert.res_status(200 , res))
        assert.is_nil(body.headers["x-consumer-username"])
      end)

      describe("Consumer" , function()
        it("associates a consumer by oauth2 username" , function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_consumer",
            headers = {
              ["Host"] = "introspection.test"
            }
          })

          local body = cjson.decode(assert.res_status(200 , res))
          assert.equal("bob" , body.headers["x-consumer-username"])
          assert.is_string(body.headers["x-consumer-id"])
          assert.is_nil(res.headers["x-ratelimit-limit-minute"])
        end)

        it("associates oauth2 client_id to consumer #custom_id", function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_consumer_client_id",
            headers = {
              ["Host"] = "introspection_client_id.test",
            }
          })

          local body = cjson.decode(assert.res_status(200 , res))
          assert.equal("kongsumer" , body.headers["x-consumer-custom-id"])
          assert.is_string(body.headers["x-consumer-id"])
          assert.is_nil(res.headers["x-ratelimit-limit-minute"])
        end)

        it("ensure cache is invalidated for consumer #custom_id added after introspection request", function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_consumer_client_id_not_added_initially",
            headers = {
              ["Host"] = "introspection_client_id_not_added_initially.test",
            }
          })
          local body = cjson.decode(assert.res_status(200 , res))
          assert.equal("kongsumer_not_added_initially" , body.headers["x-credential-client-id"])
          assert.is_nil(body.headers["x-credential-identifier"])

          -- Consumer response headers custom-id, username, and consumer-id should not be available
          assert.is_nil(body.headers["x-consumer-custom-id"])
          assert.is_nil(body.headers["x-consumer-id"])
          assert.is_nil(body.headers["x-consumer-username"])

          -- Add the missing consumer and re-execute the intronspection
          res = assert(admin_client:send {
            method = "POST",
            path = "/consumers",
            body = {
              custom_id = "kongsumer_not_added_initially",
              username = "post_kongsumer"
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })
          local id = cjson.decode(assert.res_status(201 , res))["id"]

          res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_consumer_client_id_not_added_initially",
            headers = {
              ["Host"] = "introspection_client_id_not_added_initially.test",
            }
          })
          body = cjson.decode(assert.res_status(200 , res))
          assert.equal(body.headers["x-consumer-custom-id"], body.headers["x-credential-client-id"])
          assert.equal("kongsumer_not_added_initially" , body.headers["x-consumer-custom-id"])
          assert.equal(id, body.headers["x-consumer-id"])
          assert.equal("post_kongsumer", body.headers["x-consumer-username"])
        end)

        it("invokes other consumer-specific plugins" , function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_consumer_limited",
            headers = {
              ["Host"] = "introspection.test"
            }
          })

          assert.response(res).has.status(200)
          local value = assert.request(res).has.header("x-consumer-username")
          assert.equal("limited-bob", value)
          assert.request(res).has.header("x-another-header")
        end)
      end)

      describe("upstream headers" , function()
        it("appends upstream headers" , function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_complex",
            headers = {
              ["Host"] = "introspection.test"
            }
          })

          local body = cjson.decode(assert.res_status(200 , res))
          assert.equal("valid_complex" , body.uri_args.access_token)
          assert.equal("some_client_id" , body.headers["x-credential-client-id"])
          assert.equal("some_username" , body.headers["x-credential-identifier"])
          assert.equal("some_scope" , body.headers["x-credential-scope"])
          assert.equal("some_sub" , body.headers["x-credential-sub"])
          assert.equal("some_aud" , body.headers["x-credential-aud"])
          assert.equal("some_iss" , body.headers["x-credential-iss"])
          assert.equal("some_exp" , body.headers["x-credential-exp"])
          assert.equal("some_iat" , body.headers["x-credential-iat"])
        end)

        it("appends custom upstream headers" , function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_complex",
            headers = {
              ["Host"] = "introspection6.test"
            }
          })

          local body = cjson.decode(assert.res_status(200 , res))
          assert.equal("valid_complex", body.uri_args.access_token)
          assert.equal("some_client_id", body.headers["x-credential-client-id"])
          assert.equal("some_username", body.headers["x-credential-identifier"])
          assert.equal("some_scope", body.headers["x-credential-scope"])
          assert.equal("some_sub", body.headers["x-credential-sub"])
          assert.equal("some_aud", body.headers["x-credential-aud"])
          assert.equal("some_iss", body.headers["x-credential-iss"])
          assert.equal("some_exp", body.headers["x-credential-exp"])
          assert.equal("some_iat", body.headers["x-credential-iat"])
          assert.equal("bar", body.headers["x-credential-foo"])
          assert.equal("baz", body.headers["x-credential-bar"])
        end)

        it("skips appending unconfigured custom upstream headers" , function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_complex",
            headers = {
              ["Host"] = "introspection6.test"
            }
          })

          local body = cjson.decode(assert.res_status(200 , res))
          assert.equal("valid_complex", body.uri_args.access_token)
          assert.equal("some_client_id", body.headers["x-credential-client-id"])
          assert.equal("some_username", body.headers["x-credential-identifier"])
          assert.equal("some_scope", body.headers["x-credential-scope"])
          assert.equal("some_sub", body.headers["x-credential-sub"])
          assert.equal("some_aud", body.headers["x-credential-aud"])
          assert.equal("some_iss", body.headers["x-credential-iss"])
          assert.equal("some_exp", body.headers["x-credential-exp"])
          assert.equal("some_iat", body.headers["x-credential-iat"])
          assert.equal("bar", body.headers["x-credential-foo"])
          assert.Nil(body.headers["x-credential-baz"])
        end)
      end)

      describe("hide credentials" , function()
        it("appends upstream headers" , function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_complex&hello=marco",
            headers = {
              ["Host"] = "introspection2.test"
            }
          })

          local body = cjson.decode(assert.res_status(200 , res))
          assert.is_nil(body.uri_args.access_token)
          assert.equal("some_client_id" , body.headers["x-credential-client-id"])
          assert.equal("some_username" , body.headers["x-credential-identifier"])
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
              ["Host"] = "introspection.test"
            }
          })

          assert.res_status(401 , res)
        end)
        it("should overrride auth" , function()
          local res = assert(client:send {
            method = "OPTIONS",
            path = "/request",
            headers = {
              ["Host"] = "introspection5.test"
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
              ["Host"] = "introspection3.test"
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
              ["Host"] = "introspection3.test"
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
              ["Host"] = "introspection4.test"
            }
          })
          assert.response(res).has.status(500)
        end)
      end)
    end)
  end)



  describe("Plugin: oauth2-introspection (hooks) #" .. strategy, function()
    local client , admin_client
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      local bp = helpers.get_db_utils(db_strategy, nil, {"oauth2-introspection"})

      local route1 = bp.routes:insert {
        name = "route-1",
        hosts = { "introspection.test" },
      }
      bp.plugins:insert {
        name = "oauth2-introspection",
        route = { id = route1.id },
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          ttl = 1
        }
      }

      bp.consumers:insert {
        username = "bob"
      }

      assert(helpers.start_kong({
        database = db_strategy,
        plugins = "bundled,oauth2-introspection",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures))

      client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    describe("Consumer" , function()
      it("invalidates a consumer by username" , function()
        local res = assert(client:send {
          method = "GET",
          path = "/request?access_token=valid_consumer",
          headers = {
            ["Host"] = "introspection.test"
          }
        })

        local body = cjson.decode(assert.res_status(200 , res))
        assert.equal("bob" , body.headers["x-consumer-username"])
        local consumer_id = body.headers["x-consumer-id"]
        assert.is_string(consumer_id)

        -- Deletes the consumer
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/" .. consumer_id,
          headers = {
            ["Host"] = "introspection.test"
          }
        })
        assert.res_status(204 , res)

        -- ensure cache is invalidated
        helpers.wait_until(function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_consumer",
            headers = {
              ["Host"] = "introspection.test"
            }
          })
          local body = cjson.decode(assert.res_status(200 , res))
          return body.headers["x-consumer-username"] == nil
        end)
      end)
    end)
  end)


  describe("Plugin: oauth2-introspection (multiple-auth) #" .. strategy, function()
    local client , user1 , user2 , anonymous , admin_client
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      local bp = helpers.get_db_utils(db_strategy, nil, {--"introspection-endpoint",
                                                      "oauth2-introspection"})

      local route1 = bp.routes:insert {
        name = "route-1",
        hosts = { "logical-and.test" },
      }
      bp.plugins:insert {
        name = "key-auth",
        route = { id = route1.id },
      }
      bp.plugins:insert {
        name = "oauth2-introspection",
        route = { id = route1.id },
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          ttl = 1
        }
      }

      anonymous = bp.consumers:insert {
        username = "Anonymous",
      }
      user1 = bp.consumers:insert {
        username = "bob",
      }
      user2 = bp.consumers:insert {
        username = "alice",
      }
      bp.keyauth_credentials:insert {
        key = "mouse",
        consumer = { id = user2.id },
      }

      local route2 = bp.routes:insert {
        name = "route-2",
        hosts = { "logical-or.test" },
      }
      bp.plugins:insert {
        name = "oauth2-introspection",
        route = { id = route2.id },
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          ttl = 1,
          anonymous = anonymous.id,
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route2.id },
        config = {
          anonymous = anonymous.id,
        },
      }

      assert(helpers.start_kong({
        database = db_strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,oauth2-introspection",
      }, nil, nil, fixtures))

      client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
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
            ["Host"] = "logical-and.test",
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
            ["Host"] = "logical-and.test",
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
            ["Host"] = "logical-and.test"
          }
        })
        assert.res_status(401 , res)
      end)

      it("fails 401, with no credential provided" , function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "logical-and.test",
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
            ["Host"] = "logical-or.test",
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
            ["Host"] = "logical-or.test",
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
            ["Host"] = "logical-or.test",
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
            ["Host"] = "logical-or.test",
          }
        })
        local body = cjson.decode(assert.res_status(200 , res))
        assert.not_nil(body.headers["x-anonymous-consumer"])
        local id = body.headers["x-consumer-id"]
        assert.equal(id , anonymous.id)
      end)
    end)
  end)

  describe("Plugin: oauth2-introspection: #regression #" .. strategy, function()
    local client, admin_client
    lazy_setup(function()
      local db_strategy = strategy ~= "off" and strategy or nil
      local bp = helpers.get_db_utils(db_strategy, nil, {"oauth2-introspection"})

      local route = bp.routes:insert {
        name = "route",
        hosts = { "test.test" },
      }
      bp.plugins:insert {
        name = "oauth2-introspection",
        route = { id = route.id },
        config = {
          anonymous = "",
          introspection_url = introspection_url,
          authorization_value = "hello",
          introspect_request = false,
          ttl = 1
        }
      }

      assert(helpers.start_kong({
        database = db_strategy,
        plugins = "bundled,oauth2-introspection",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures))

      client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end
      if client then
        client:close()
      end
      assert(helpers.stop_kong())
    end)

    it("any body should not cause 500 #FTI-4974" , function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?access_token=valid",
        headers = {
          ["Host"] = "test.test",
          ["Authorization"] = "hello",
          ["Content-Type"] = "application/json",
        },
        body = [["string"]]
      })
      assert.res_status(400, res)
    end)
  end)
end

