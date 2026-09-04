local PLUGIN_NAME = "standard-webhooks"
local helpers = require "spec.helpers"
local swh = require "kong.plugins.standard-webhooks.internal"

local SECRET = "MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"
local MESSAGE_ID = "msg_p5jXN8AQM9LWM0D4loKWxJek"

for _, strategy in helpers.all_strategies() do
  local client

  describe(PLUGIN_NAME .. ": (Access)", function()
    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {"routes", "services", "plugins"}, {PLUGIN_NAME})

      local r = bp.routes:insert({
        paths = {"/"}
      })

      bp.plugins:insert{
        route = r,
        name = PLUGIN_NAME,
        config = {
          secret_v1 = SECRET
        }
      }

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- write & load declarative config, only if 'strategy=off'
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil
      }))
    end)
    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    it("rejects missing headers", function()
      local res = client:post("/", {
        headers = {
          ["Content-Type"] = "application/json",
          ["webhook-id"] = MESSAGE_ID,
          ["webhook-timestamp"] = math.floor(ngx.now())
        },
        body = {
          foo = "bar"
        }
      })

      assert.response(res).has.status(400)
    end)

    it("rejects invalid timestamp", function()
      local res = client:post("/", {
        headers = {
          ["Content-Type"] = "application/json",
          ["webhook-id"] = MESSAGE_ID,
          ["webhook-signature"] = "asdf",
          ["webhook-timestamp"] = "XYZ"
        },
        body = {
          foo = "bar"
        }
      })

      assert.response(res).has.status(400)
    end)

    it("rejects missing body", function()
      local res = client:post("/", {
        headers = {
          ["Content-Type"] = "application/json",
          ["webhook-id"] = MESSAGE_ID,
          ["webhook-signature"] = "asdf",
          ["webhook-timestamp"] = math.floor(ngx.now())
        }
      })

      assert.response(res).has.status(400)
    end)

    it("accepts correct signature", function()
      local ts = math.floor(ngx.now())
      local signature = swh.sign(SECRET, MESSAGE_ID, ts, '{"foo":"bar"}')

      local res = client:post("/", {
        headers = {
          ["Content-Type"] = "application/json",
          ["webhook-id"] = MESSAGE_ID,
          ["webhook-signature"] = signature,
          ["webhook-timestamp"] = ts
        },
        body = {
          foo = "bar"
        }
      })

      assert.response(res).has.status(200)
    end)

    it("fails because the timestamp tolerance is exceeded", function()
      local ts = math.floor(ngx.now()) - 6 * 60
      local signature = swh.sign(SECRET, MESSAGE_ID, ts, '{"foo":"bar"}')

      local res = client:post("/", {
        headers = {
          ["Content-Type"] = "application/json",
          ["webhook-id"] = MESSAGE_ID,
          ["webhook-signature"] = signature,
          ["webhook-timestamp"] = ts
        },
        body = {
          foo = "bar"
        }
      })

      assert.response(res).has.status(400)
    end)
  end)
end
