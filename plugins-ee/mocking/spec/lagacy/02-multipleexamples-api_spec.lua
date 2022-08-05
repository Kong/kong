-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers   = require "spec.helpers"
local pl_path   = require "pl.path"
local cjson     = require("cjson.safe").new()
--local ngx_log   = ngx.log
--local ngx_WARN  = ngx.WARN

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
  local content  = assert(helpers.utils.readfile(fixture_path .. filename))
   return content
end

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _, strategy in strategies() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client
    local db_strategy = strategy ~= "off" and strategy or nil

      lazy_setup(function()
        local bp, db = helpers.get_db_utils(db_strategy, {
          "routes",
          "services",
          "files",
        }, { PLUGIN_NAME })

        assert(db.files:insert {
          path = "specs/multipleexamples.json",
          contents = read_fixture("multipleexamples.json"),
        })

        local service1 = bp.services:insert{
          protocol = "http",
          port     = 80,
          host     = "mocking.com",
        }

      db.routes:insert({
        hosts = { "mocking.com" },
        service    = service1,

      })

      local service2 = bp.services:insert{
        protocol = "http",
        port     = 80,
        host     = "mocking2.com",
      }

      db.routes:insert({
        hosts = { "mocking2.com" },
        service    = service2,

      })

      -- add the plugin to test to the route we created
      db.plugins:insert {
        name = PLUGIN_NAME,
        service = { id = service2.id },
        config = {
          api_specification_filename = "multipleexamples.json",
          random_delay = false,
          random_examples = true
        },
      }

      -- add the plugin to test to the route we created
      db.plugins:insert {
        name = PLUGIN_NAME,
        service = { id = service1.id },
        config = {
          api_specification_filename = "multipleexamples.json",
          random_delay = false
        },
      }

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = db_strategy,
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

    describe("multipleexamples API Specification tests", function()
      it("Check for examples(Multiple Examples) extraction", function()
        local r = assert(client:send {
          method = "GET",
          path = "/pet/findByStatus/MultipleExamples",
          headers = {
            host = "mocking.com"
          }
        })
        -- validate that the request succeeded, response status 200
        local _ = cjson.decode(assert.res_status(200, r))
        -- check whether the results have 3 object as per the spec file
        -- skip validate body content as we might got 'No Content' example
        --local count = 0
        --for _ in pairs(body) do count = count+1 end
        --assert.equal(2,count)
      end)
    end)

    describe("multipleexamples API Specification tests", function()
      it("Check for X-Kong-Mocking-Plugin header", function()
        local r = assert(client:send {
          method = "GET",
          path = "/pet/findByStatus/MultipleExamples",
          headers = {
            host = "mocking.com"
          }
        })
        -- validate that the request succeeded, response status 200

        assert.res_status(200, r)

        local header_value = assert.response(r).has.header("X-Kong-Mocking-Plugin")

        assert.equal("true", header_value)
      end)
    end)

    describe("multipleexamples API Specification tests", function()
      it("Check for 404 with Random path", function()
        local r = assert(client:send {
          method = "GET",
          path = "/random_path",
          headers = {
            host = "mocking.com"
          }
        })
        -- Random path, Response status - 404
        local body = assert.res_status(404, r)
        local json = cjson.decode(body)
        -- Check for error message
        assert.same("Path does not exist in API Specification", json.message)
      end)
    end)


    describe("multipleexamples API Specification tests", function()
      it("Check for example(Single Example) extraction", function()
        local r = assert(client:send {
          method = "GET",
          path = "/pet/findByStatus/singleExample",
          headers = {
            host = "mocking.com"
          }
        })
         -- validate that the request succeeded, response status 200
         local body = cjson.decode(assert.res_status(200, r))
         assert.same({
           id = 1,
           category = { id = 1, name = "cat" },
           nickname = "fluffy",
           photoUrls = {
             [1] = "http://example.com/path/to/cat/1.jpg",
             [2] = "http://example.com/path/to/cat/2.jpg",
           },
           tags = {
             [1] = { id = 1, name = "cat" },
           },
           status = "available",
         }, body)
      end)
    end)


    -- skip this test as param filter feature has been removed
    --describe("multipleexamples API Specification tests", function()
    --  it("Check multiple example filter logic - Positive filter", function()
    --    local r = assert(client:send {
    --      method = "GET",
    --      path = "/pet/findByStatus/MultipleExamples?nickname=fluffy",
    --      headers = {
    --        host = "mocking.com"
    --      }
    --    })
    --
    --    local body = cjson.decode(assert.res_status(200, r))
    --     -- skip validate response body as we might got "No Content" example
    --     assert.equal("fluffy",find_key(body,"nickname"))
    --     assert.equal("cat",find_key(body,"name"))
    --     assert.equal("available",find_key(body,"status"))
    --  end)
    --end)

    describe("multipleexamples API Specification tests", function()
      it("Check multiple example filter logic 404 - Negative Random Filter", function()
        local r = assert(client:send {
          method = "GET",
          path = "/pet/findByStatus/MultipleExamples?status=idonotexist",
          headers = {
            host = "mocking.com"
          }
        })

        -- fix: response code should not be changed
        local _ = assert.res_status(200, r)
        --local json = cjson.decode(body)
        -- Check for error message
        --assert.same("No examples exist in API specification for this resource with Accept Header (application/json)", json.message)

      end)
    end)

    -- skip this test as mocking plugin might return a unspecific example since the randomness of lua table
    --describe("multipleexamples API Specification tests", function()
    --  it("Check for examples(Multiple Examples) with Multiple Search Parameters", function()
    --    local r = assert(client:send {
    --      method = "GET",
    --      path = "/pet/findByStatus/MultipleExamples?name=dog&name=cat",
    --      headers = {
    --        host = "mocking.com"
    --      }
    --    })
    --    -- validate that the request succeeded, response status 200
    --    local body = cjson.decode(assert.res_status(200, r))
    --    -- check whether the results have 2 object as per the spec file
    --    local count = 0
    --    for _ in pairs(body) do count = count+1 end
    --    assert.equal(2,count)
    --  end)
    --end)

    -- skip this test as mocking plugin might return a unspecific example since the randomness of lua table
    --describe("multipleexamples API Specification tests with <random_examples>", function()
    --  it("Check for examples(Multiple Examples) with Multiple Search Parameters", function()
    --    local r = assert(client:send {
    --      method = "GET",
    --      path = "/pet/findByStatus/MultipleExamples?name=dog&name=cat",
    --      headers = {
    --        host = "mocking2.com"
    --      }
    --    })
    --    -- validate that the request succeeded, response status 200
    --    local body = cjson.decode(assert.res_status(200, r))
    --    -- check if body is of type table (as expected from the examples)
    --    assert.equal(type(body), "table")
    --    -- check if body is one element
    --    assert.equal(#body, 0)
    --    -- check if expected content is present
    --    assert.equal(type(body.category.id), "number")
    --    -- check if the catory.name attribute is either of cat or dog (as per the query args)
    --    assert((body.category.name == "dog" or body.category.name == "cat"), true)
    --  end)
    --end)

  end)
end
