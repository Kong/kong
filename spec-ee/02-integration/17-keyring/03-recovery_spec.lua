-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local pl_file = require "pl.file"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy({"postgres"}) do
describe("Keyring recovery #" .. strategy, function()
  local admin_client

  lazy_setup(function()
    helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "plugins",
      "consumers",
      "upstreams",
      "targets",
      "keyring_meta",
      "keyring_keys",
    })

    assert(helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      keyring_enabled = "on",
      keyring_strategy = "cluster",
      keyring_recovery_public_key = "spec-ee/fixtures/keyring/pub.pem",
    }))

    admin_client = helpers.admin_client()
  end)

  lazy_teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  describe("ensure keyring works", function()
    it("/keyring", function()
      helpers.wait_until(function()
        local client = helpers.admin_client()
        local res = assert(client:send {
          method = "GET",
          path = "/keyring",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        client:close()
        return json.active ~= nil
      end, 5)

      local res = assert(admin_client:send {
        method = "GET",
        path = "/keyring/active",
      })
      assert.res_status(200, res)
    end)

    it("correct privat key recovers keys", function()
      local privkey_pem, err = pl_file.read("spec-ee/fixtures/keyring/key.pem")
      assert.is_nil(err)

      local res = assert(admin_client:send {
        method = "POST",
        path = "/keyring/recover",
        body = {
          ["recovery_private_key"] = privkey_pem,
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("successfully recovered 1 keys", json.message)
    end)

    it("wrong private key doesn't recover keys", function()
      local key = assert(require("resty.openssl.pkey").new({type="EC"}))
      local privkey_pem = assert(key:to_PEM("private"))

      local res = assert(admin_client:send {
        method = "POST",
        path = "/keyring/recover",
        body = {
          ["recovery_private_key"] = privkey_pem,
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("successfully recovered 0 keys", json.message)
      assert.equal(1, json.not_recovered and #json.not_recovered or 0)
    end)
  end)

end)
end
