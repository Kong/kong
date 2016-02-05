local inspect = require "inspect"

local utils = require "spec.spec_helpers"
local Factory = require "kong.dao.factory"

local api_tbl = {
  name = "mockbin",
  request_host = "mockbin.com",
  request_path = "/mockbin",
  strip_request_path = true,
  upstream_url = "https://mockbin.com"
}

utils.for_each_dao(function(db_type, default_options)
  describe("Model (APIs) with DB: "..db_type, function()
    local factory, apis
    setup(function()
      factory = Factory(db_type, default_options)
      apis = factory.apis
      assert(factory:run_migrations())
    end)
    after_each(function()
      --factory:drop_schema()
    end)

    describe("insert()", function()
      it("should insert a valid API", function()
        local api, err = apis:insert(api_tbl)
        print(inspect(err))
        print(inspect(api))
      end)
    end)
  end)
end)
