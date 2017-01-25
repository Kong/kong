local helpers = require "spec.helpers"
local Factory = require "kong.dao.factory"
local dao_helpers = require "spec.02-integration.02-dao.helpers"


local factory


local function insert_apis(arr)
  if type(arr) ~= "table" then
    return error("expected arg #1 to be a table", 2)
  end

  factory:truncate_tables()

  for i = 1, #arr do
    assert(factory.apis:insert(arr[i]))
  end
end


dao_helpers.for_each_dao(function(kong_config)

  describe("upstream timeouts", function()
    local client

    setup(function()
      factory = assert(Factory.new(kong_config))
      assert(factory:run_migrations())
      factory:truncate_tables()

      insert_apis {
        {
          name = "api-1",
          methods = "HEAD",
          upstream_url = "http://httpbin.org",
          upstream_connect_timeout = 1, -- ms
        },
        {
          name = "api-2",
          methods = "POST",
          upstream_url = "http://httpbin.org",
          upstream_send_timeout = 100, -- ms
        },
        {
          name = "api-3",
          methods = "GET",
          upstream_url = "http://httpbin.org",
          upstream_read_timeout = 100, -- ms
        }
      }

      assert(helpers.start_kong({
        database = kong_config.database
      }))
    end)

    teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("upstream_connect_timeout", function()
      it("sets upstream connect timeout value", function()
        local res = assert(client:send {
          method = "HEAD",
          path = "/",
        })

        assert.res_status(504, res)
      end)
    end)

    describe("upstream_read_timeout", function()
      it("sets upstream read timeout value", function()
        local res = assert(client:send {
          method = "GET",
          path = "/delay/2",
        })

        assert.res_status(504, res)
      end)
    end)

    describe("upstream_send_timeout", function()
      it("sets upstream send timeout value", function()
        local res = assert(client:send {
          method = "POST",
          path = "/post",
          body = {
            huge = string.rep("a", 2^20)
          },
          headers = { ["Content-Type"] = "application/json" }
        })

        assert.res_status(504, res)
      end)
    end)
  end)

end) -- for_each_dao
