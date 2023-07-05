local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"

local fmt = string.format

-- no cassandra support
for _, strategy in helpers.each_strategy({ "postgres" }) do

describe("WASMX admin API [#" .. strategy .. "]", function()
  local admin
  local bp, db
  local service, route

  lazy_setup(function()
    bp, db = helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "filter_chains",
    })

    db.filter_chains:load_filters({
      { name = "tests" },
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


  local function reset_filter_chains()
    db.filter_chains:truncate()
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


  describe("/filter-chains", function()

    describe("POST", function()
      lazy_setup(reset_filter_chains)

      it("creates a filter chain", function()
        local res = admin:post("/filter-chains", {
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
      lazy_setup(reset_filter_chains)

      it("returns a collection of filter chains", function()
        local res = admin:get("/filter-chains")
        assert.response(res).has.status(200)

        local body = assert.response(res).has.jsonbody()
        assert.same({ data = {}, next = ngx.null }, body)

       local chain = assert(bp.filter_chains:insert({
          filters = { { name = "tests" } },
          service = { id = service.id },
          tags = { "a" },
        }, { nulls = true }))

        res = admin:get("/filter-chains")
        assert.response(res).has.status(200)

        body = assert.response(res).has.jsonbody()
        assert.equals(1, #body.data, "unexpected number of filter chain entities")
        assert.same(chain, body.data[1])

        assert.response(
          admin:post("/filter-chains", json {
            filters = { { name = "tests" } },
            route = { id = route.id },
            tags = { "b" },
          })
        ).has.status(201)

        res = admin:get("/filter-chains")
        assert.response(res).has.status(200)

        body = assert.response(res).has.jsonbody()
        assert.equals(2, #body.data, "unexpected number of filter chain entities")
      end)
    end)

    unsupported("PATCH",  "/filter-chains")
    unsupported("PUT",    "/filter-chains")
    unsupported("DELETE", "/filter-chains")
  end)

  for _, key in ipairs({ "id", "name" }) do

  describe("/filter-chains/:" .. key, function()
    describe("GET", function()
      local chain

      lazy_setup(function()
        chain = bp.filter_chains:insert({
          service = assert(bp.services:insert({})),
          filters = { { name = "tests" } },
        }, { nulls = true })
      end)

      it("fetches a filter chain", function()
        local res = admin:get("/filter-chains/" .. chain[key])
        assert.response(res).has.status(200)
        local got = assert.response(res).has.jsonbody()
        assert.same(chain, got)
      end)

      it("returns 404 if not found", function()
        assert.response(
          admin:get("/filter-chains/" .. utils.uuid())
        ).has.status(404)
      end)
    end)

    describe("PATCH", function()
      local chain

      lazy_setup(function()
        chain = bp.filter_chains:insert({
          service = assert(bp.services:insert({})),
          filters = { { name = "tests" } },
        }, { nulls = true })
      end)

      it("updates a filter chain in-place", function()
        assert.equals(ngx.null, chain.tags)
        assert.is_true(chain.enabled)

        local res = admin:patch("/filter-chains/" .. chain[key], json {
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
      local chain

      lazy_setup(function()
        chain = bp.filter_chains:insert({
          service = assert(bp.services:insert({})),
          filters = { { name = "tests" } },
        }, { nulls = true })
      end)

      it("removes a filter chain", function()
        local res = admin:delete("/filter-chains/" .. chain[key])
        assert.response(res).has.status(204)

        assert.response(
          admin:get("/filter-chains/" .. chain[key])
        ).has.status(404)
      end)

    end)

    unsupported("POST", "/filter-chains/" .. utils.uuid())
  end)

  end -- each { "id", "name" }


  -- * /services/:service/filter-chains
  -- * /services/:service/filter-chains/:chain
  -- * /routes/:route/filter-chains
  -- * /routes/:route/filter-chains/:chain
  for _, rel in ipairs({ "service", "route" }) do

  describe(fmt("/%ss/:%s/filter-chains", rel, rel), function()
    local path, entity

    before_each(function()
      if rel == "service" then
        entity = assert(bp.services:insert({}))
      else
        entity = assert(bp.routes:insert({ hosts = { "wasm.test" } }))
      end

      path = fmt("/%ss/%s/filter-chains", rel, entity.id)
    end)

    describe("POST", function()
      it("creates a " .. rel .. " filter chain", function()
        local res = admin:post(path, {
          headers = { ["Content-Type"] = "application/json" },
          body = {
            filters = { { name = "tests" } },
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
      it("returns existing " .. rel .. " filter chains", function()
        local res = admin:get(path)
        assert.response(res).has.status(200)

        local body = assert.response(res).has.jsonbody()
        assert.same({ data = {}, next = ngx.null }, body)

        res = admin:post(path, json {
          filters = { { name = "tests" } },
          tags = { "a" },
        })

        assert.response(res).has.status(201)
        local chain = assert.response(res).has.jsonbody()

        res = admin:get(path)
        assert.response(res).has.status(200)

        body = assert.response(res).has.jsonbody()
        assert.equals(1, #body.data, "unexpected number of filter chain entities")
        assert.same(chain, body.data[1])
      end)
    end)

    unsupported("PATCH",  path)
    unsupported("PUT",    path)
    unsupported("DELETE", path)
  end)

  describe(fmt("/%ss/:%s/filter-chains/:chain", rel, rel), function()
    local path, entity
    local chain

    before_each(function()
      if rel == "service" then
        entity = assert(bp.services:insert({}))
        chain = assert(bp.filter_chains:insert({
          service = entity,
          filters = { { name = "tests" } },
        }, { nulls = true }))

      else
        entity = assert(bp.routes:insert({ hosts = { "wasm.test" } }))
        chain = assert(bp.filter_chains:insert({
          route = entity,
          filters = { { name = "tests" } },
        }, { nulls = true }))
      end

      path = fmt("/%ss/%s/filter-chains/", rel, entity.id)
    end)

    describe("GET", function()
      it("fetches a filter chain", function()
        local res = admin:get(path .. chain.id)
        assert.response(res).has.status(200)
        local got = assert.response(res).has.jsonbody()
        assert.same(chain, got)
      end)

      it("returns 404 if not found", function()
        assert.response(
          admin:get(path .. utils.uuid())
        ).has.status(404)
      end)
    end)

    describe("PATCH", function()
      it("updates a filter chain in-place", function()
        assert.equals(ngx.null, chain.tags)
        assert.is_true(chain.enabled)

        local res = admin:patch(path .. chain.id, json {
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
      it("removes a filter chain", function()
        local res = admin:delete(path .. chain.id)
        assert.response(res).has.status(204)

        assert.response(
          admin:get(path .. chain.id)
        ).has.status(404)
      end)

    end)
  end)

  end -- each relation (service, route)


end)

end -- each strategy
