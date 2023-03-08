-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ssl_fixtures = require "spec.fixtures.ssl"
local helpers = require "spec.helpers"
local cjson = require "cjson"

local get_name
do
  local n = 0
  get_name = function()
    n = n + 1
    return string.format("name%04d.test", n)
  end
end


for _, strategy in helpers.each_strategy() do

describe("Admin API: #" .. strategy, function()
  local client
  local bp
  local ws1, ws2, cert1, cert2
  local n1 = get_name()
  local n2 = get_name()

  local function check_certificates()
    local res  = client:get("/one/certificates")
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    assert.equal(1, #json.data)
    assert.equal(1, #json.data[1].snis)
    assert.equal(n1, json.data[1].snis[1])
  end

  before_each(function()
    client = assert(helpers.admin_client())
  end)

  after_each(function()
    if client then
      client:close()
    end
  end)

  lazy_setup(function()
    bp = helpers.get_db_utils(strategy, {
      "snis",
      "certificates",
      "workspaces",
    })

    ws1 = assert(bp.workspaces:insert {
      name = "one"
    })

    ws2 = assert(bp.workspaces:insert {
      name = "two"
    })

    cert1 = assert(bp.certificates:insert_ws ({
      cert  = ssl_fixtures.cert,
      key  = ssl_fixtures.key,
    }, ws1))

    assert(bp.snis:insert_ws ({
      name = n1,
      certificate = cert1,
    }, ws1))

    cert2 = assert(bp.certificates:insert_ws ({
      cert  = ssl_fixtures.cert,
      key  = ssl_fixtures.key,
    }, ws2))

    assert(bp.snis:insert_ws ({
      name = n2,
      certificate = cert2,
    }, ws2))

    assert(helpers.start_kong({
      database = strategy,
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  describe("/certificates", function()

    describe("POST", function()

      it("returns a conflict when a pre-existing sni on a different workspace is detected", function()
        local res = client:post("/one/certificates", {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = { n2, },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.matches("snis: " .. n2 .. " already associated with existing certificate", json.message)

        -- make sure we didn't add the certificate, or any snis
        check_certificates()
      end)

    end)
  end)

  describe("/certificates/cert_id_or_sni", function()

    describe("PUT", function()
      it("returns a conflict when a pre-existing sni on a different workspace is detected", function()
        local res = client:put("/one/certificates/" .. cert1.id, {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = { n2, },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.matches("snis: " .. n2 .. " already associated with existing certificate", json.message)

        -- make sure we didn't add the certificate, or any snis
        check_certificates()
      end)
    end)

    describe("PATCH", function()
      it("returns a conflict when a pre-existing sni on a different workspace is detected", function()
        local res = client:patch("/one/certificates/" .. cert1.id, {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = { n2, },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.matches("snis: " .. n2 .. " already associated with existing certificate", json.message)

        -- make sure we didn't add the certificate, or any snis
        check_certificates()
      end)
    end)
  end)
end)

end
