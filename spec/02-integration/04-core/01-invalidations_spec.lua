-- simply adapted for ngx_lua busted from hooks_spec.lua

local helpers = require "spec.helpers"
local cache = require "kong.tools.database_cache"
local cjson = require "cjson"

describe("Cache entities invalidations", function()
  local proxy_client, admin_client
  setup(function()
    helpers.dao:truncate_tables()
    helpers.execute "pkill nginx; pkill serf"
    assert(helpers.prepare_prefix())
    assert(helpers.start_kong())

    proxy_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
    admin_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.admin_port))
  end)
  teardown(function()
    if proxy_client and admin_client then
      proxy_client:close()
      admin_client:close()
    end
    helpers.stop_kong()
    helpers.clean_prefix()
  end)

  describe("APIs", function()
    it("invalidates ALL_APIS_BY_DICT key on API creation", function()
      assert(helpers.dao.apis:insert {
        request_host = "my-api.com",
        upstream_url = "http://mockbin.com"
      })

      -- populate APIs cache
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "my-api.com"
        }
      })
      assert.res_status(200, res)

      res = assert(admin_client:send {
        method = "GET",
        path = "/cache/"..cache.all_apis_by_dict_key()
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json.by_dns["my-api.com"])

      -- new API
    end)
  end)
end)
