local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local wasm_fixtures = require "spec.fixtures.wasm"

-- no cassandra support
for _, strategy in helpers.each_strategy({ "postgres" }) do

describe("WASMX admin API [#" .. strategy .. "]", function()
  local admin
  local db

  lazy_setup(function()
    local _
    _, db = helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "wasm_filter_chains",
    })

    wasm_fixtures.build()

    assert(helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      wasm = true,
      wasm_filters_path = wasm_fixtures.TARGET_PATH,
    }))


    admin = helpers.admin_client()
  end)

  lazy_teardown(function()
    if admin then admin:close() end
    helpers.stop_kong(nil, true)
  end)


  local function reset_db()
    db.wasm_filter_chains:truncate()
  end


  local function unsupported(method, path)
    describe(method, function()
      it("is not supported", function()
        local res = assert(admin:send {
          method = method,
          path = path,
        })
        assert.response(res).has.status(405)
      end)
    end)
  end


  local function json(body)
    return {
      headers = { ["Content-Type"] = "application/json" },
      body = body,
    }
  end


  describe("/wasm/filter-chains", function()
    before_each(reset_db)

    describe("POST", function()
      it("creates a filter chain", function()
        local res = admin:post("/wasm/filter-chains", {
          headers = { ["Content-Type"] = "application/json" },
          body = {
            name = "test",
            filters = { { name = "tests" } },
          },
        })

        assert.response(res).has.status(201)
        local body = assert.response(res).has.jsonbody()

        assert.is_string(body.id)
        assert.truthy(utils.is_valid_uuid(body.id))

        assert.equals("test", body.name)
        assert.equals(1, #body.filters)
        assert.equals("tests", body.filters[1].name)
      end)
    end)

    describe("GET", function()
      it("returns a collection of filter chains", function()
        local res = admin:get("/wasm/filter-chains")
        assert.response(res).has.status(200)

        local body = assert.response(res).has.jsonbody()
        assert.same({ data = {}, next = ngx.null }, body)

        res = admin:post("/wasm/filter-chains", json {
          name = "test",
          filters = { { name = "tests" } },
        })

        assert.response(res).has.status(201)
        local chain = assert.response(res).has.jsonbody()

        res = admin:get("/wasm/filter-chains")
        assert.response(res).has.status(200)

        body = assert.response(res).has.jsonbody()
        assert.equals(1, #body.data, "unexpected number of filter chain entities")
        assert.same(chain, body.data[1])

        assert.response(
          admin:post("/wasm/filter-chains", json {
            name = "test-2",
            filters = { { name = "tests" } },
          })
        ).has.status(201)

        res = admin:get("/wasm/filter-chains")
        assert.response(res).has.status(200)

        body = assert.response(res).has.jsonbody()

        table.sort(body.data, function(a, b) return a.name < b.name end)

        assert.equals(2, #body.data, "unexpected number of filter chain entities")
        assert.equals("test", body.data[1].name)
        assert.equals("test-2", body.data[2].name)
      end)
    end)

    unsupported("PATCH",  "/wasm/filter-chains")
    unsupported("PUT",    "/wasm/filter-chains")
    unsupported("DELETE", "/wasm/filter-chains")
  end)

  describe("/wasm/filter-chains/:chain", function()
    describe("GET", function()
      local id, name, chain

      lazy_setup(function()
        reset_db()

        id = utils.uuid()
        name = "test"
        local res = admin:post("/wasm/filter-chains", json {
          id = id,
          name = name,
          filters = { { name = "tests" } },
        })

        assert.response(res).has.status(201)
        chain = assert.response(res).has.jsonbody()
      end)

      lazy_teardown(reset_db)

      it("fetches a filter chain by ID", function()
        local res = admin:get("/wasm/filter-chains/" .. id)
        assert.response(res).has.status(200)
        local got = assert.response(res).has.jsonbody()
        assert.same(chain, got)
      end)

      it("fetches a filter chain by name", function()
        local res = admin:get("/wasm/filter-chains/" .. name)
        assert.response(res).has.status(200)
        local got = assert.response(res).has.jsonbody()
        assert.same(chain, got)
      end)

      it("returns 404 if not found", function()
        assert.response(
          admin:get("/wasm/filter-chains/" .. "i-do-not-exist")
        ).has.status(404)

        assert.response(
          admin:get("/wasm/filter-chains/" .. utils.uuid())
        ).has.status(404)
      end)
    end)

    describe("PATCH", function()
      local id, name, chain

      lazy_setup(function()
        reset_db()

        id = utils.uuid()
        name = "test"
        local res = admin:post("/wasm/filter-chains", json {
          id = id,
          name = name,
          filters = { { name = "tests" } },
        })

        assert.response(res).has.status(201)
        chain = assert.response(res).has.jsonbody()
      end)

      lazy_teardown(reset_db)

      it("updates a filter chain in-place", function()
        assert.equals(ngx.null, chain.tags)
        assert.is_true(chain.enabled)

        local res = admin:patch("/wasm/filter-chains/" .. id, json {
          tags = { "foo", "bar" },
          enabled = false,
          filters = {
            { name = "tests", config = "123", enabled = true },
            { name = "tests", config = "456", enabled = false },
          },
        })

        assert.response(res).has.status(200)
        local patched = assert.response(res).has.jsonbody()

        assert.same({ "foo", "bar" }, patched.tags)
        assert.is_false(patched.enabled)
        assert.equals(2, #patched.filters)
        assert.same({ name = "tests", config = "123", enabled = true },
                    patched.filters[1])
        assert.same({ name = "tests", config = "456", enabled = false },
                    patched.filters[2])
      end)
    end)

    describe("DELETE", function()
      lazy_setup(reset_db)
      lazy_teardown(reset_db)

      local id, name
      before_each(function()
        id = utils.uuid()
        name = "test"

        assert.response(admin:post("/wasm/filter-chains", json {
          id = id,
          name = name,
          filters = { { name = "tests" } },
        })).has.status(201)

        assert.response(
          admin:get("/wasm/filter-chains/" .. id)
        ).has.status(200)
      end)


      it("removes a filter chain by ID", function()
        local res = admin:delete("/wasm/filter-chains/" .. id)
        assert.response(res).has.status(204)

        assert.response(
          admin:get("/wasm/filter-chains/" .. id)
        ).has.status(404)

        assert.response(
          admin:get("/wasm/filter-chains/" .. name)
        ).has.status(404)
      end)

      it("removes a filter chain by name", function()
        local res = admin:delete("/wasm/filter-chains/" .. name)
        assert.response(res).has.status(204)

        assert.response(
          admin:get("/wasm/filter-chains/" .. id)
        ).has.status(404)

        assert.response(
          admin:get("/wasm/filter-chains/" .. name)
        ).has.status(404)
      end)

    end)

    unsupported("POST", "/wasm/filter-chains/" .. utils.uuid())
  end)
end)

end -- each strategy
