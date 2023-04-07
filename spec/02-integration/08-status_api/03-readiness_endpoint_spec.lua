local helpers = require "spec.helpers"
local cjson = require "cjson"


for _, strategy in helpers.all_strategies() do
describe("Status API - with strategy #" .. strategy, function()
  local client

  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    assert(helpers.start_kong {
      status_listen = "127.0.0.1:9500",
      plugins = "admin-api-method",
    })
    client = helpers.http_client("127.0.0.1", 9500, 20000)
  end)

  lazy_teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)
 
  describe("status readiness endpoint", function()
    it("can return a status code", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/ready"
      })
      ngx.sleep(10)
      local body = assert.res_status(200, res)
      assert.same(body, '')
    end)
  end)

end)
end
