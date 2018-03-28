local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"

local dao_helpers = require "spec.02-integration.03-dao.helpers"
local DAOFactory = require "kong.dao.factory"

local conf_loader = require "kong.conf_loader"
local kong_config = assert(conf_loader(helpers.test_conf_path, {
                                         database = "postgres"
}))


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
        client = assert(helpers.admin_client())
      end)
      after_each(function()
        if client then client:close() end
      end)
      it("doesn't create an API when it conflicts", function()
          local res = assert(client:send {
            method = "POST",
            path = "/apis",
            body = {
              uris = "/my-uri",
              name = "my-api",
              methods = "GET",
              hosts = "my.api.com",
              upstream_url = "http://api.com"
            },
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.res_status(201, res)

          os.execute("sleep 5")
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
                         headers = {["Content-Type"] = "application/json"}
          })

          body = assert.res_status(201, res)

          res = assert(client:send {
                         method = "POST",
                         path = "/foo/apis",
                         body = {
                           uris = "/my-uri",
                           name = "my-api",
                           methods = "GET",
                           hosts = "my.api.com",
                           upstream_url = "http://api.com"
                         },
                         headers = {["Content-Type"] = "application/json"}
          })
          assert.res_status(409, res)
      end)
    end)
  end)
end)
