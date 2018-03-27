local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"

local dao_helpers = require "spec.02-integration.03-dao.helpers"
local DAOFactory = require "kong.dao.factory"

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with application/json", test_json)
end

dao_helpers.for_each_dao(function(kong_config)
describe("Admin API #" .. kong_config.database, function()
  local client
  local dao
  setup(function()
    dao = assert(DAOFactory.new(kong_config))
    helpers.run_migrations(dao)

    assert(helpers.start_kong{
      database = kong_config.database
    })
  end)
  teardown(function()
    helpers.stop_kong()
  end)

  describe("/apis", function()
    describe("POST", function()
      before_each(function()
        dao:truncate_tables()
        client = assert(helpers.admin_client())
      end)
      after_each(function()
        if client then client:close() end
      end)
      it_content_types("doesn't create an API when it conflicts", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/apis",
            body = {
              uris = "/my-uri",
              name = "my-api",
              hosts = "my.api.com",
              upstream_url = "http://api.com"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("my-api", json.name)
          assert.same({ "my.api.com" }, json.hosts)
          assert.equal("http://api.com", json.upstream_url)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.is_nil(json.paths)
          assert.False(json.preserve_host)
          assert.True(json.strip_uri)
          assert.equals(5, json.retries)

          res = assert(client:send {
                         method = "POST",
                         path = "/workspaces",
                         body = {
                           name = "foo",
                         },
                         headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)

          -- res = assert(client:send {
          --                method = "POST",
          --                path = "/foo/apis",
          --                body = {
          --                  name = "my-api",
          --                  uris = "/my-uri",
          --                  hosts = "my.api.com",
          --                  upstream_url = "http://api.com"
          --                },
          --                headers = {["Content-Type"] = content_type}
          -- })
          -- assert.res_status(409, res)

        end
      end)
    end)
  end)
end)
end)
