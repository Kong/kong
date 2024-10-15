local helpers = require "spec.helpers"

local FILTER_PATH = assert(helpers.test_conf.wasm_filters_path)

-- no cassandra support
for _, strategy in helpers.each_strategy({ "postgres" }) do

describe("missing filters in the config [#" .. strategy .. "]", function()
  local bp
  local service, route

  lazy_setup(function()
    require("kong.runloop.wasm").enable({
      { name = "tests",
        path = FILTER_PATH .. "/tests.wasm",
      },
      { name = "response_transformer",
        path = FILTER_PATH .. "/response_transformer.wasm",
      },
    })

    bp = helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "filter_chains",
    })

    service = assert(bp.services:insert {
      name = "wasm-test",
    })

    route = assert(bp.routes:insert {
      service = service,
      paths = { "/" },
    })

    assert(bp.filter_chains:insert {
      name = "test",
      route = route,
      filters = {
        {
          name = "response_transformer",
          config = require("cjson").encode {
            append = {
              headers = {
                "x-wasm-test:my-value",
              },
            },
          }
        },
        {
          name = "tests",
          config = nil,
        },
        {
          name = "response_transformer",
          config = require("cjson").encode {
            append = {
              headers = {
                "x-wasm-test:my-value",
              },
            },
          }
        }
      }
    })
  end)

  lazy_teardown(function()
    helpers.clean_prefix()
  end)

  it("causes Kong to fail to start", function()
    local ok, err = helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      wasm_filters = "tests",
      wasm = true,
    })

    assert.falsy(ok, "expected `kong start` to fail")
    assert.string(err)
    assert.matches("response_transformer", err)
  end)
end)

end -- each strategy
