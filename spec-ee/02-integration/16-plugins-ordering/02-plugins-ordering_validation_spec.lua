-- this software is copyright kong inc. and its licensors.
-- use of the software is subject to the agreement between your organization
-- and kong inc. if there is no such agreement, use is governed by and
-- subject to the terms of the kong master software license agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ end of license 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"


for _, strategy in helpers.all_strategies({"postgres", "off"}) do

  local client
  describe("validate plugin ordering schemas", function()
    lazy_setup(function()
      helpers.get_db_utils(nil, {})
      assert(helpers.start_kong {
        database = strategy,
        plugins = "bundled",
        license_path = "spec-ee/fixtures/mock_license.json",
      })
      client = helpers.admin_client(10000)
    end)

    lazy_teardown(function()
      if client then client:close() end
      helpers.stop_kong()
    end)

    it("validate no ordering schema", function()
      local res = assert(client:post("/schemas/plugins/validate", {
        body = {
          name = "key-auth",
          config = {
            key_names = {"foo"},
          },
        },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(200, res)
    end)

    it("validate empty ordering schema", function()
      local res = assert(client:post("/schemas/plugins/validate", {
        body = {
          name = "key-auth",
          ordering = {},
          config = {
            key_names = {"foo"},
          },
        },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(200, res)
    end)

    it("validate ordering schema with incorrect subfields", function()
      local res = assert(client:post("/schemas/plugins/validate", {
        body = {
          name = "key-auth",
          ordering = {
            unknownfield = {
            }
          },
          config = {
            key_names = {"foo"},
          },
        },
        headers = {["Content-Type"] = "application/json"}
      }))
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.equal("schema violation (ordering: expected one of: before, after)", json.message)
    end)

    it("validate ordering schema with dependency markers of the wrong type", function()
      local res = assert(client:post("/schemas/plugins/validate", {
        body = {
          name = "key-auth",
          ordering = {
            after = "any-plugin" -- expects a table
          },
          config = {
            key_names = {"foo"},
          },
        },
        headers = {["Content-Type"] = "application/json"}
      }))
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.equal("schema violation (ordering: expected a map)", json.message)
    end)

    it("validate ordering schema with unknown phases", function()
      local res = assert(client:post("/schemas/plugins/validate", {
        body = {
          name = "key-auth",
          ordering = {
            after = {
              unknown_phase = { -- phases needs to be knonwn
              }
            }
          },
          config = {
            key_names = {"foo"},
          },
        },
        headers = {["Content-Type"] = "application/json"}
      }))
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.equal("schema violation (ordering: expected one of: access)", json.message)
    end)

    it("validate ordering schema with wrong ordering.after.access type", function()
      local res = assert(client:post("/schemas/plugins/validate", {
        body = {
          name = "key-auth",
          ordering = {
            after = {
              access = "needs to be a table"
            }
          },
          config = {
            key_names = {"foo"},
          },
        },
        headers = {["Content-Type"] = "application/json"}
      }))
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.equal("schema violation (ordering: expected an array)", json.message)
    end)

    it("validate ordering schema with correct structure but unknown plugin", function()
      local res = assert(client:post("/schemas/plugins/validate", {
        body = {
          name = "key-auth",
          ordering = {
            after = {
              access = {
                "any-plugin"
              }
            }
          },
          config = {
            key_names = {"foo"},
          },
        },
        headers = {["Content-Type"] = "application/json"}
      }))
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.matches("schema violation", json.message)
    end)

    it("validate ordering schema with correct structure", function()
      local res = assert(client:post("/schemas/plugins/validate", {
        body = {
          name = "key-auth",
          ordering = {
            after = {
              access = {
                "basic-auth"
              }
            }
          },
          config = {
            key_names = {"foo"},
          },
        },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(200, res)
    end)

    pending("validate ordering schema with duplicate anchors", function()
      local res = assert(client:post("/schemas/plugins/validate", {
        body = {
          name = "key-auth",
          ordering = {
            after = {
              access = {
                "basic-auth",
                "basic-auth"
              }
            }
          },
          config = {
            key_names = {"foo"},
          },
        },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(400, res)
    end)

    pending("validate ordering schema with circular dependency -- This should fail", function()
      local res = assert(client:post("/schemas/plugins/validate", {
        body = {
          name = "key-auth",
          ordering = {
            after = {
              access = {
                "key-auth"
              },
            },
            before = {
              access = {
                "key-auth"
              }
            }
          },
          config = {
            key_names = {"foo"},
          },
        },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(400, res)
    end)
  end)
end

for _, strategy in helpers.each_strategy() do
  describe("Dynamic Plugin Ordering - Free License #" .. strategy, function()

    lazy_setup(function()
      helpers.stop_kong()

      helpers.get_db_utils(strategy)

      -- No license is present
      helpers.unsetenv("KONG_LICENSE_DATA")

      assert(helpers.start_kong({
        database  = strategy,
      }))
      client = assert(helpers.admin_client())
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      if client then
        client:close()
      end
    end)

    it("POST to setup a plugin with ordering but Kong is in free-mode", function()
      local res, _ = assert.res_status(400, assert(client:send {
        method = "POST",
        path = "/plugins",
        body = {
          name = "key-auth",
          ordering = {
            after = {
              access = {
                "basic-auth"
              }
            }
          },
          config = {
            key_names = {"foo"},
          },
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      }))
      local dres = cjson.decode(res)
      assert.same("schema violation (ordering requires a license to be used)", dres.message)
    end)
  end)
end
