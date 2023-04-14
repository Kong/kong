local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"

-- no cassandra support
for _, strategy in helpers.each_strategy({ "postgres" }) do

describe("WASMX admin API [#" .. strategy .. "]", function()
  local admin
  local db
  local service, route

  lazy_setup(function()
    local _
    _, db = helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "wasm_filter_chains",
    })

    service = assert(db.services:insert {
      name = "wasm-test",
      url = "http://wasm.test",
    })

    route = assert(db.routes:insert {
      service = { id = service.id },
      hosts = { "wasm.test" },
      paths = { "/" },
    })


    assert(helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      wasm = true,
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
            filters = { { name = "tests" } },
            service = { id = service.id },
          },
        })

        assert.response(res).has.status(201)
        local body = assert.response(res).has.jsonbody()

        assert.is_string(body.id)
        assert.truthy(utils.is_valid_uuid(body.id))

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
          filters = { { name = "tests" } },
          service = { id = service.id },
          tags = { "a" },
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
            filters = { { name = "tests" } },
            route = { id = route.id },
            tags = { "b" },
          })
        ).has.status(201)

        res = admin:get("/wasm/filter-chains")
        assert.response(res).has.status(200)

        body = assert.response(res).has.jsonbody()
        assert.equals(2, #body.data, "unexpected number of filter chain entities")
      end)
    end)

    unsupported("PATCH",  "/wasm/filter-chains")
    unsupported("PUT",    "/wasm/filter-chains")
    unsupported("DELETE", "/wasm/filter-chains")
  end)

  describe("/wasm/filter-chains/:chain", function()
    describe("GET", function()
      local id, chain

      lazy_setup(function()
        reset_db()

        id = utils.uuid()
        local res = admin:post("/wasm/filter-chains", json {
          id = id,
          filters = { { name = "tests" } },
          service = { id = service.id },
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

      it("returns 404 if not found", function()
        assert.response(
          admin:get("/wasm/filter-chains/" .. utils.uuid())
        ).has.status(404)
      end)
    end)

    describe("PATCH", function()
      local id, chain

      lazy_setup(function()
        reset_db()

        id = utils.uuid()
        local res = admin:post("/wasm/filter-chains", json {
          id = id,
          filters = { { name = "tests" } },
          service = { id = service.id },
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

      local id
      before_each(function()
        id = utils.uuid()

        assert.response(admin:post("/wasm/filter-chains", json {
          id = id,
          filters = { { name = "tests" } },
          service = { id = service.id },
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
      end)

    end)

    unsupported("POST", "/wasm/filter-chains/" .. utils.uuid())
  end)
end)

end -- each strategy
