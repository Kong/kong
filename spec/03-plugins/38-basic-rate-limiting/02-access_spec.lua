local helpers           = require "spec.helpers"

local UPSTREAM_HOST     = "localhost"
local UPSTREAM_PORT     = helpers.get_available_port()
local UPSTREAM_URL      = string.format("http://%s:%d/always_200", UPSTREAM_HOST, UPSTREAM_PORT)

local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("basic-rate-limiting", function()
    
    local bp = helpers.get_db_utils(strategy,nil,{"basic-rate-limiting"})
    local proxy_client = {}
    local https_server

    setup(function()
      https_server = helpers.https_server.new(UPSTREAM_PORT)
      https_server:start()
      
      local service = bp.services:insert {
        name = "localhost",
        url = UPSTREAM_URL
      }

      bp.routes:insert({
        name = "test",
        paths = { "/test" },
        service = { id = service.id }
      })

      bp.plugins:insert {
        name     = "basic-rate-limiting",
        config   = {
          minute   = 5,
        },
      }

      assert(helpers.start_kong( { plugins = "bundled,basic-rate-limiting" }))

    end)

    teardown(function()
      https_server:shutdown()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    describe("basic-rate-limiting", function()
      it("only allow request below the limit", function()
        
        for i = 0,4,1 do 
            local res = proxy_client:get("/test", {
                headers = {
                  ["Host"] = "localhost"
                }
              })
      
              assert.res_status(200, res)
        end

        local res = proxy_client:get("/test", {
          headers = {
            ["Host"] = "localhost"
          }
        })

        assert.res_status(429, res)

      end)
    end)
  end)
end