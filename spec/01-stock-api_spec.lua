local helpers   = require "spec.helpers"
local pl_path   = require "pl.path"
local cjson     = require("cjson.safe").new()

local PLUGIN_NAME = "mocking"

local fixture_path do
  -- this code will get debug info and from that determine the file
  -- location, so fixtures can be found based of this path
  local info = debug.getinfo(function() end)
  fixture_path = info.source
  if fixture_path:sub(1,1) == "@" then
    fixture_path = fixture_path:sub(2, -1)
  end
  fixture_path = pl_path.splitpath(fixture_path) .. "/resources/"
end


local function read_fixture(filename)
  ngx.log(ngx.WARN, "fixture path: ", fixture_path)
  local content  = assert(helpers.utils.readfile(fixture_path .. filename))
  --ngx_log(ngx_WARN, "content", content)
   return content
  --return assert(helpers.utils.readfile(fixture_path .. filename))
end

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

      lazy_setup(function()
        local bp, db = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "files",
        }, { PLUGIN_NAME })

        assert(db.files:insert {
          path = "specs/stock.json",
          contents = read_fixture("stock.json"),  
        })
        
        local service1 = bp.services:insert{
          protocol = "http",
          port     = 80,
          host     = "mocking.com",
        }
        
      local route1 = db.routes:insert({
        hosts = { "mocking.com" },
        service    = service1,

      })

      -- add the plugin to test to the route we created
      db.plugins:insert {
        name = PLUGIN_NAME,
        service = { id = service1.id },
        config = {
          api_specification_filename = "stock.json",
          random_delay = false
        },
      }

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("Stock API Specification tests", function()
      it("/stock/historical happy path", function()
        local r = assert(client:send {
          method = "GET",
          path = "/stock/historical",  -- makes mockbin return the entire request
          headers = {
            host = "mocking.com"
          }
        })
        -- validate that the request succeeded, response status 200
        --assert.response(r).has.status(200)
        local body = assert.res_status(200, r)
        ngx.log(ngx.WARN, "Body: ", body)
        local header_value = assert.response(r).has.header("X-Kong-Mocking-Plugin")
        -- validate the value of that header
        assert.equal("true", header_value)
      end)
    end)
    
    describe("Stock API Specification tests", function()
      it("/random_path Random path", function()
        local r = assert(client:send {
          method = "GET",
          path = "/random_path",
          headers = {
            host = "mocking.com"
          }
        })
        -- Random path, Response status - 404
        assert.response(r).has.status(404)
      end)
    end)

  end)
end