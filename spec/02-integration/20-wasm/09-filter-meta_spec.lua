-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"

local file = helpers.file

local TEST_FILTER_SRC = "spec/fixtures/proxy_wasm_filters/build/response_transformer.wasm"

local function json(body)
  return {
    headers = { ["Content-Type"] = "application/json" },
    body = body,
  }
end

local function post_config(client, config)
  config._format_version = config._format_version or "3.0"

  local res = client:post("/config?flatten_errors=1", json(config))

  assert.response(res).has.jsonbody()

  return res
end

local function random_name()
  return "test-" .. utils.random_string()
end


for _, strategy in helpers.each_strategy({ "postgres", "off" }) do

describe("filter metadata [#" .. strategy .. "]", function()
  local filter_path
  local admin
  local proxy

  lazy_setup(function()
    helpers.clean_prefix()

    if strategy == "postgres" then
      helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "filter_chains",
      })
    end

    filter_path = helpers.make_temp_dir()
    do
      local name = "rt_no_validation"
      assert(file.copy(TEST_FILTER_SRC, filter_path .. "/" .. name .. ".wasm"))
    end

    do
      local name = "rt_with_validation"
      assert(file.copy(TEST_FILTER_SRC, filter_path .. "/" .. name .. ".wasm"))

      assert(file.write(filter_path .. "/" .. name .. ".meta.json", cjson.encode({
        config_schema = {
          type = "object",
          properties = {
            add = {
              type = "object",
              properties = {
                headers = {
                  type = "array",
                  elements = { type = "string" },
                },
              },
              required = { "headers" },
            },
          },
          required = { "add" },
        }
      })))
    end

    assert(helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "off",
      wasm = true,
      wasm_filters_path = filter_path,
      nginx_main_worker_processes = 1,
    }))

    admin = helpers.admin_client()
    proxy = helpers.proxy_client()

    helpers.clean_logfile()
  end)

  lazy_teardown(function()
    if admin then admin:close() end
    if proxy then proxy:close() end

    helpers.stop_kong()

    if filter_path and os.getenv("KONG_DONT_CLEAN") ~= "1" then
      helpers.dir.rmtree(filter_path)
    end
  end)

  describe("config validation -", function()
    local create_filter_chain

    if strategy == "off" then
      create_filter_chain = function(route_host, filter_chain)
        return post_config(admin, {
          services = {
            { name = random_name(),
              url = helpers.mock_upstream_url,
              routes = {
                { name = random_name(),
                  hosts = { route_host },
                  filter_chains = { filter_chain }
                },
              },
            },
          },
        })
      end

    else
      create_filter_chain = function(route_host, filter_chain)
        local res = admin:post("/services", json {
          name = random_name(),
          url = helpers.mock_upstream_url,
        })

        assert.response(res).has.status(201)

        local service = assert.response(res).has.jsonbody()

        res = admin:post("/routes", json {
          name = random_name(),
          hosts = { route_host },
          service = { id = service.id },
        })

        assert.response(res).has.status(201)

        local route = assert.response(res).has.jsonbody()

        res = admin:post("/routes/" .. route.id .. "/filter-chains",
                         json(filter_chain))

        assert.response(res).has.jsonbody()

        return res
      end
    end

    it("filters with config schemas are validated", function()
      local res = create_filter_chain(random_name(), {
        name = random_name(),
        filters = {
          {
            name = "rt_with_validation",
            json_config = {}, -- empty
          },
        },
      })

      assert.response(res).has.status(400)
      local body = assert.response(res).has.jsonbody()

      if strategy == "off" then
        assert.is_table(body.flattened_errors)
        assert.same(1, #body.flattened_errors)

        local err = body.flattened_errors[1]
        assert.is_table(err)
        assert.same("filter_chain", err.entity_type)
        assert.same({
          {
            field = "filters.1.config",
            message = "property add is required",
            type = "field"
          }
        }, err.errors)

      else
        assert.same({
          filters = {
            {
              json_config = "property add is required"
            }
          }
        }, body.fields)
      end

      local host = random_name() .. ".test"
      res = create_filter_chain(host, {
        name = random_name(),
        filters = {
          {
            name = "rt_with_validation",
            json_config = {
              add = {
                headers = {
                  "x-foo:123",
                },
              },
            },
          },
        },
      })

      assert.response(res).has.status(201)

      assert.eventually(function()
        res = proxy:get("/status/200", { headers = { host = host } })
        assert.response(res).has.status(200)
        assert.response(res).has.header("x-foo")
      end).has_no_error()
    end)

    it("filters without config schemas are not validated", function()
      local host = random_name() .. ".test"

      local res = create_filter_chain(host, {
        name = random_name(),
        filters = {
          {
            name = "rt_no_validation",
            json_config = {
              add = {
                headers = 1234,
              },
            },
          },
        },
      })

      assert.response(res).has.status(201)

      assert.eventually(function()
        res = proxy:get("/status/200", { headers = { host = host } })
        assert.response(res).has.no.header("x-foo")
        assert.logfile().has.line("failed parsing filter config", true, 0)
      end).has_no_error()
    end)

  end)

end)

describe("filter metadata [#" .. strategy .. "] startup errors -", function()
  local filter_path
  local filter_name = "test-filter"
  local meta_path
  local conf

  lazy_setup(function()
    if strategy == "postgres" then
      helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "filter_chains",
      })
    end
  end)

  before_each(function()
    filter_path = helpers.make_temp_dir()
    assert(file.copy(TEST_FILTER_SRC, filter_path .. "/" .. filter_name .. ".wasm"))
    meta_path = filter_path .. "/" .. filter_name .. ".meta.json"

    conf = {
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "off",
      wasm = true,
      wasm_filters_path = filter_path,
      nginx_main_worker_processes = 1,
    }

    helpers.clean_prefix()
    helpers.prepare_prefix()
  end)

  after_each(function()
    helpers.kill_all()

    if filter_path and os.getenv("KONG_DONT_CLEAN") ~= "1" then
      helpers.dir.rmtree(filter_path)
    end
  end)

  describe("kong start", function()
    it("fails when filter.meta.json is not a file", function()
      assert(helpers.dir.makepath(meta_path))
      local ok, err = helpers.start_kong(conf)
      assert.falsy(ok)

      assert.matches("Failed to load metadata for one or more filters", err, nil, true)
      assert.matches(filter_name, err, nil, true)
      assert.matches(meta_path, err, nil, true)
      assert.matches("path exists but is not a file", err, nil, true)
    end)

    it("fails when filter.meta.json is not vaild json", function()
      assert(file.write(meta_path, "oops!"))
      local ok, err = helpers.start_kong(conf)
      assert.falsy(ok)

      assert.matches("Failed to load metadata for one or more filters", err, nil, true)
      assert.matches(filter_name, err, nil, true)
      assert.matches(meta_path, err, nil, true)
      assert.matches("JSON decode error", err, nil, true)
    end)

    it("fails when filter.meta.json is not semantically valid", function()
      assert(file.write(meta_path, cjson.encode({
        config_schema = {
          type = "i am not a valid type",
        },
      })))
      local ok, err = helpers.start_kong(conf)
      assert.falsy(ok)

      assert.matches("Failed to load metadata for one or more filters", err, nil, true)
      assert.matches(filter_name, err, nil, true)
      assert.matches(meta_path, err, nil, true)
      assert.matches("file contains invalid metadata", err, nil, true)
    end)
  end)
end)

end -- each strategy
