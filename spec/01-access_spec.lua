local helpers = require "spec.helpers"
local version = require("version").version or require("version")
local pl_path = require "pl.path"

local lyaml       = require "lyaml"
local cjson       = require("cjson.safe").new()
local kong = kong
local ngx_log = ngx.log
local ngx_WARN = ngx.WARN

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
  ngx_log(ngx_WARN, "fixture path: ", fixture_path)
  local content  = assert(helpers.utils.readfile(fixture_path .. filename))
  --ngx_log(ngx_WARN, "content", content)
   return content
  --return assert(helpers.utils.readfile(fixture_path .. filename))
end


local PLUGIN_NAME = "mocking"

local WORKING_DIR = "/Users/steve.young/Documents/GitHub/kong-plugin-mocking"


for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

      lazy_setup(function()
        --local f = assert(io.open(fixture_path .. "/resources/stock.json"))
        --local str = f:read("*a")
        --f:close()

        local bp, db = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "files",
        })

        assert(db.files:insert {
          path = "default:specs/stock.json",
          contents = read_fixture("stock.json"),  
          --ngx_log(ngx_WARN, "contents: ", read_fixture("stock.json"))
        })

        assert(db.files:insert {
          path = "defualt:specs/multipleexamples.json",
          contents = read_fixture("multipleexamples.json"),  
          --ngx_log(ngx_WARN, "contents: ", read_fixture("stock.json"))
        })
        
        local service1 = bp.services:insert{
          protocol = "http",
          port     = 80,
          host     = "mockbin.com",
        }
        
      -- Inject a test route. No need to create a service, there is a default
      -- service which will echo the request.
      local route1 = db.routes:insert({
        hosts = { "test1.com" },
        service    = service1,

      })

      -- add the plugin to test to the route we created
      db.plugins:insert {
        name = "mocking",
        route = { id = route1.id },
        config = {
          api_specification_filename = "multipleexamples.json",
        },
      }
      local route2 = db.routes:insert({
        hosts = { "test2.com" },
      })

      -- add the plugin to test to the route we created
      db.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = {
          api_specification_filename = " ",
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



    describe(PLUGIN_NAME.." ", function()
      it("gets a X-Kong-Mocking-Plugin header", function()
        local r = assert(client:send {
          method = "GET",
          path = "/pet/findByStatus/MultipleExamples",  -- makes mockbin return the entire request
          headers = {
            host = "test1.com"
          }
        })
        -- validate that the request succeeded, response status 200
        --assert.response(r).has.status(200)
        local body = assert.res_status(200, r)
        ngx_log(ngx_WARN, "Body: ", body)
        local json = cjson.decode(body)
        --ngx_log(ngx_WARN, "json value: ", json)
        local upStreamHeaderVal  = json.headers["X-Kong-Mocking-Plugin"]
        -- check mocking plugin
        assert.equal("true",upStreamHeaderVal)
      end)
    end)



    describe(PLUGIN_NAME.." ", function()
      it("Empty spec filename check", function()
        local r = assert(client:send {
          method = "GET",
          path = "/pet/findByStatus/MultipleExamples",  -- makes mockbin return the entire request
          headers = {
            host = "test1.com"
          }
        })
        -- validate that the request succeeded, response status 200
        assert.res_status(404, r)

      end)
    end)

  end)
end
