-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("ai-rate-limiting-advanced API", function()
  local admin_client, bp

  lazy_setup(function()
    bp = helpers.get_db_utils(nil, nil, {"ai-rate-limiting-advanced"})

    assert(bp.routes:insert {
      name  = "test",
      hosts = { "test1.test" },
    })

    assert(helpers.start_kong({
      plugins = "ai-rate-limiting-advanced",
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    admin_client = helpers.admin_client()
  end)

  lazy_teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  describe("POST", function()
    it("errors with size/limit mismatch", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/routes/test/plugins/",
        body = {
          name = "ai-rate-limiting-advanced",
          config = {
            llm_providers = {{
              name = "openai",
              window_size = 10,
              limit = 10,
            },{
              window_size = 60,
            }},
            sync_rate = 10,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(400, res))
      assert.same("required field missing", body.fields.config.llm_providers[2].name)
      assert.same("required field missing", body.fields.config.llm_providers[2].limit)
    end)

    it("errors with missing size/limit configs", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/routes/test/plugins/",
        body = {
          name = "ai-rate-limiting-advanced",
          config = {
            llm_providers = {{
              name = "openai",
              limit = 10,
            }},
            sync_rate = 10,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(400, res))
      assert.same("required field missing", body.fields.config.llm_providers[1].window_size)
    end)

    it("transparently sorts limit/window_size pairs", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/plugins",
        body = {
          name = "ai-rate-limiting-advanced",
          config = {
            strategy = "cluster",
            llm_providers = {{
              name = "openai",
              window_size = 3600,
              limit = 10,
            },{
              name = "mistral",
              window_size = 60,
              limit = 10,
            }},
            sync_rate = 10,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(201, res)
      local json = cjson.decode(body)

      assert.same( "openai", json.config.llm_providers[1].name)
      assert.same( 3600, json.config.llm_providers[1].window_size)
      assert.same( 10, json.config.llm_providers[1].limit)

      assert.same( "mistral", json.config.llm_providers[2].name)
      assert.same( 60, json.config.llm_providers[2].window_size)
      assert.same( 10, json.config.llm_providers[2].limit)
    end)
  end)

  describe("PATCH", function()
    local plugin_id

    lazy_setup(function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/routes/test/plugins/",
        body = {
          name = "ai-rate-limiting-advanced",
          config = {
            strategy = "cluster",
            llm_providers = {{
              name = "openai",
              window_size = 10,
              limit = 10,
            }},
            sync_rate = 10,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(201, res)
      plugin_id = cjson.decode(body).id
    end)

    it("errors with size/limit mismatch", function()
      local res = assert(admin_client:send {
        method = "PATCH",
        path = "/routes/test/plugins/" .. plugin_id,
        body = {
          name = "ai-rate-limiting-advanced",
          config = {
            strategy = "cluster",
            llm_providers = {{
              name = "openai",
              window_size = 10,
              limit = 10,
            },{
              name = "azure",
            }},
            sync_rate = 10,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(400, res))
      assert.same("required field missing", body.fields.config.llm_providers[2].window_size)
      assert.same("required field missing", body.fields.config.llm_providers[2].limit)
    end)

    it("accepts an update without requiring size/limit configs", function()
      local res = assert(admin_client:send {
        method = "PATCH",
        path = "/routes/test/plugins/" .. plugin_id,
        body = {
          name = "ai-rate-limiting-advanced",
          config = {
            sync_rate = 10,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.same(10, body.config.llm_providers[1].window_size)
      assert.same(10, body.config.llm_providers[1].limit)
    end)

    it("accepts an update chaings size/limit configs", function()
      local res = assert(admin_client:send {
        method = "PATCH",
        path = "/routes/test/plugins/" .. plugin_id,
        body = {
          name = "ai-rate-limiting-advanced",
          config = {
            llm_providers = {{
              name = "openai",
              window_size = 20,
              limit = 20,
            },{
              name = "mistral",
              window_size = 20,
              limit = 20,
            }},
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.same( "openai", body.config.llm_providers[1].name)
      assert.same(20, body.config.llm_providers[1].window_size)
      assert.same(20, body.config.llm_providers[1].limit)

      assert.same( "mistral", body.config.llm_providers[2].name)
      assert.same(20, body.config.llm_providers[2].window_size)
      assert.same(20, body.config.llm_providers[2].limit)

      -- check that sync_rate, which we touched before, it still the same
      assert.same(10, body.config.sync_rate)
    end)
  end)
end)