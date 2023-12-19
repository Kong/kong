-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local pl_path = require "pl.path"

local PLUGIN_NAME = "mocking"

local fixture_path
do
  -- this code will get debug info and from that determine the file
  -- location, so fixtures can be found based of this path
  local info = debug.getinfo(function()
  end)
  fixture_path = info.source
  if fixture_path:sub(1, 1) == "@" then
    fixture_path = fixture_path:sub(2, -1)
  end
  fixture_path = pl_path.splitpath(fixture_path) .. "/fixtures/"
end

local function read_fixture(filename)
  local content = assert(helpers.utils.readfile(fixture_path .. filename))
  return content
end

local function structure_like(source, target)
  for k, v in pairs(source) do
    local source_type = type(v)
    local target_value = target[k]
    if source_type ~= type(target_value) then
      return false, string.format("%s(%s) and %s(%s) are not the same type", v, source_type, target_value, type(target_value))
    end
    if source_type == "table" then
      local ok, err = structure_like(v, target_value)
      if not ok then
        return false, err
      end
    end
  end
  return true, nil
end

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      }, { PLUGIN_NAME })

      local service1 = assert(bp.services:insert {
        protocol = "http",
        port = 12345,
        host = "127.0.0.1",
      })

      local route1 = assert(db.routes:insert({
        hosts = { "example.com" },
        service = service1,
      }))
      assert(db.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          api_specification = read_fixture("reference-oas.yaml"),
        },
      })

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. PLUGIN_NAME,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("simple reference", function()
      it("/ref-case-1", function()
        local res = assert(client:send {
          method = "POST",
          path = "/ref-case-1",
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(200)
        local body = assert.response(res).has.jsonbody()
        local ok, err = structure_like(body, { key_string = "" })
        assert.is_nil(err)
        assert.is_true(ok)
      end)

      it("/ref-case-2", function()
        local res = assert(client:send {
          method = "POST",
          path = "/ref-case-2",
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(200)
        local body = assert.response(res).has.jsonbody()
        local ok, err = structure_like(body, { { key_string = "" }, { key_string = "" } })
        assert.is_nil(err)
        assert.is_true(ok)
      end)

      it("/ref-case-3", function()
        local res = assert(client:send {
          method = "POST",
          path = "/ref-case-3",
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(200)
        local body = assert.response(res).has.jsonbody()
        local ok, err = structure_like(body, {
          key_integer = 0,
          key_boolean = false,
          simple = {
            key_string = ""
          }
        })
        assert.is_nil(err)
        assert.is_true(ok)
      end)
    end)

    describe("recursive reference", function()
      it("/recursive-ref-case-1", function()
        local res = assert(client:send {
          method = "POST",
          path = "/recursive-ref-case-1",
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(200)
        local body = assert.response(res).has.jsonbody()
        local ok, err = structure_like(body, {
          value = "",
          node = {
            value = "",
            node = {
              value = "",
              node = nil -- end recursive
            }
          }
        })
        assert.is_nil(err)
        assert.is_true(ok)
      end)

      it("/recursive-ref-case-2", function()
        local res = assert(client:send {
          method = "POST",
          path = "/recursive-ref-case-2",
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(200)
        local body = assert.response(res).has.jsonbody()
        local ok, err = structure_like(body, {
          differentFields = { "" },
          securityEligibilityRules = {
            operation = "",
            constraint = "",
            leaves = {
              {
                operation = "",
                constraint = "",
                leaves = {
                  {
                    operation = "",
                    constraint = "",
                    leaves = { -- end recursive
                    }
                  }
                }
              }
            }
          },
        })
        assert.is_nil(err)
        assert.is_true(ok)
      end)

      it("/recursive-ref-case-3", function()
        local res = assert(client:send {
          method = "POST",
          path = "/recursive-ref-case-3",
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(200)
        local body = assert.response(res).has.jsonbody()
        local ok, err = structure_like(body, {
          {
            title = "",
            profile = {
              createdDate = "",
              customer = {
                title = "",
                profile = {
                  createdDate = "",
                  customer = {
                    title = "",
                    profile = {
                      createdDate = "",
                      customer = nil -- recursive end
                    }
                  }
                }
              }
            }
          }
        })
        assert.is_nil(err)
        assert.is_true(ok)
      end)
    end)
  end)
end
