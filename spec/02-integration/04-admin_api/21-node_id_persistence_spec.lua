local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("persist node_id to filesystem [#" .. strategy .. "]", function()
    local admin_client

    lazy_setup(function()
      assert(helpers.start_kong({
        database = strategy,
      }))
      admin_client = assert(helpers.admin_client())
    end)

    lazy_teardown(function()
      admin_client:close()
      helpers.stop_kong(nil, true)
    end)

    it("node_id should be same after kong restarts", function()
      local res = admin_client:get("/", {
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(200, res)
      local node_id_a = require("cjson").decode(body).node_id

      assert(helpers.restart_kong({
        database = strategy,
      }))

      admin_client = assert(helpers.admin_client())
      local res = admin_client:get("/", {
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(200, res)
      local node_id_b = require("cjson").decode(body).node_id
      assert.equals(node_id_a, node_id_b)
      local node_id, err = helpers.file.read(helpers.test_conf.prefix .. "/node.id/http")
      assert.is_nil(err)
      assert.equals(node_id, node_id_a)
    end)
  end)
end
