local helpers = require "spec.helpers"
local cjson = require "cjson"


local function post_config(client, config)
  config._format_version = config._format_version or "3.0"

  local res = client:post("/config?flatten_errors=1", {
    body = config,
    headers = {
      ["Content-Type"] = "application/json"
    },
  })

  assert.response(res).has.jsonbody()

  assert.logfile().has.no.line("[emerg]", true, 0)
  assert.logfile().has.no.line("[crit]",  true, 0)
  assert.logfile().has.no.line("[alert]", true, 0)
  assert.logfile().has.no.line("[error]", true, 0)
  assert.logfile().has.no.line("[warn]",  true, 0)

  return res
end


local function expect_entity_error(res, err)
  assert.response(res).has.status(400)

  local json = assert.response(res).has.jsonbody()
  assert.is_table(json.flattened_errors)

  local found = false


  for _, entity in ipairs(json.flattened_errors) do
    assert.is_table(entity.errors)
    for _, elem in ipairs(entity.errors) do
      if elem.type == "entity" then
        assert.same(err, elem.message)
        found = true
        break
      end
    end
  end

  assert.is_true(found, "expected '" .. err .. "' message in response")
end


describe("#wasm declarative config", function()
  local admin
  local proxy
  local header_name = "x-wasm-dbless"

  lazy_setup(function()
    assert(helpers.start_kong({
      database = "off",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      wasm = true,
    }))

    admin = helpers.admin_client()
    proxy = helpers.proxy_client()
  end)

  lazy_teardown(function()
    if admin then admin:close() end
    if proxy then proxy:close() end
    helpers.stop_kong()
  end)

  it("permits valid filter chain entities", function()
    local res = post_config(admin, {
      services = {
        { name = "test",
          url = helpers.mock_upstream_url,
          routes = {
            { name = "test",
              hosts = { "wasm.test" }
            },
          },
          filter_chains = {
            { name = "test",
              filters = {
                { name = "response_transformer",
                  config = cjson.encode {
                    append = {
                      headers = {
                        header_name .. ":hello!"
                      },
                    },
                  },
                }
              },
            },
          },
        },
      },
    })

    assert.response(res).has.status(201)

    assert
      .eventually(function()
        res = proxy:get("/status/200", {
          headers = { host = "wasm.test" },
        })

        res:read_body()

        if res.status ~= 200 then
          return nil, { exp = 200, got = res.status }
        end

        local header = res.headers[header_name]

        if header == nil then
          return nil, header_name ..  " header not present in the response"

        elseif header ~= "hello!" then
          return nil, { exp = "hello!", got = header }
        end

        return true
      end)
      .is_truthy("filter-chain created by POST /config is active")
  end)

  it("rejects filter chains with non-existent filters", function()
    local res = post_config(admin, {
      services = {
        { name = "test",
          url = "http://wasm.test/",
          filter_chains = {
            { name = "test",
              filters = {
                { name = "i_do_not_exist" }
              },
            },
          },
        },
      },
    })

    assert.response(res).has.status(400)

    local json = assert.response(res).has.jsonbody()

    assert.is_table(json.flattened_errors)

    assert.same(1, #json.flattened_errors)
    assert.is_table(json.flattened_errors[1])

    assert.is_table(json.flattened_errors[1].errors)
    assert.same(1, #json.flattened_errors[1].errors)

    local err = assert.is_table(json.flattened_errors[1].errors[1])

    assert.same("filters.1.name", err.field)
    assert.same("field", err.type)
    assert.same("no such filter", err.message)
  end)
end)


describe("#wasm declarative config (no installed filters)", function()
  local client
  local tmp_dir

  lazy_setup(function()
    tmp_dir = helpers.make_temp_dir()

    assert(helpers.start_kong({
      database = "off",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      wasm = true,
      wasm_filters_path = tmp_dir,
    }))

    client = helpers.admin_client()
  end)

  lazy_teardown(function()
    if client then client:close() end
    helpers.stop_kong()
    helpers.dir.rmtree(tmp_dir)
  end)

  it("warns clients that no filters are installed", function()
    local res = post_config(client, {
      services = {
        { name = "test",
          url = "http://wasm.test/",
          filter_chains = {
            { name = "test",
              filters = {
                { name = "i_do_not_exist" }
              },
            },
          },
        },
      },
    })

    expect_entity_error(res, "no wasm filters are available")
  end)
end)

describe("#wasm declarative config (wasm = off)", function()
  local client

  lazy_setup(function()
    assert(helpers.start_kong({
      database = "off",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      wasm = "off",
    }))

    client = helpers.admin_client()
  end)

  lazy_teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  it("warns clients that wasm is disabled", function()
    local res = post_config(client, {
      services = {
        { name = "test",
          url = "http://wasm.test/",
          filter_chains = {
            { name = "test",
              filters = {
                { name = "i_do_not_exist" }
              },
            },
          },
        },
      },
    })

    expect_entity_error(res, "wasm support is not enabled")
  end)
end)
