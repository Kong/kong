local helpers = require "spec.helpers"

describe("dbless node_id persistence #off", function()
  local admin_client

  lazy_setup(function()
    assert(helpers.start_kong({
      database   = "off",
    }))

    admin_client = assert(helpers.admin_client())
  end)

  lazy_teardown(function()
    admin_client:close()
    helpers.stop_kong(nil, true)
  end)

  it("loads the lmdb config on restarts", function()
    local res = admin_client:get("/",{
      headers = {
        ["Content-Type"] = "application/json"
      }
    })
    local body = assert.res_status(200, res)
    local node_id_a = require("cjson").decode(body).node_id

    assert(helpers.restart_kong({
      database   = "off",
    }))

    admin_client:close()
    admin_client = assert(helpers.admin_client())

    local res = admin_client:get("/",{
      headers = {
        ["Content-Type"] = "application/json"
      }
    })
    local body = assert.res_status(200, res)
    local node_id_b = require("cjson").decode(body).node_id

    assert.equal(node_id_a, node_id_b)
  end)
end)
