local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Admin API", function()
  local admin_client

  setup(function()
    local api = assert(helpers.dao.apis:insert {
      name = "mockbin",
      hosts = { "mockbin.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      api_id = api.id,
      name = "api-autogen",
    })

    assert(helpers.start_kong({
      custom_plugins = "api-autogen",
    }))
    admin_client = helpers.admin_client()
  end)
  teardown(function()
    if admin_client then admin_client:close() end
    helpers.stop_kong()
  end)

  describe("Auto-Generated routes", function()
    local entity_id, entity2_id
    describe("/{entity}/", function()
      it("GET", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/some_entities/"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(0, json.total)
        assert.equal(0, #json.data)
      end)
      it("POST", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/some_entities/",
          body = {
            name = "bob"
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal("bob", json.name)
        entity_id = json.id
      end)
      it("PUT (create new)", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/some_entities/",
          body = {
            name = "bob2"
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal("bob2", json.name)
        entity2_id = json.id
        assert.is_not.equal(entity_id, entity2_id)
      end)
      it("GET", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/some_entities/"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)
    end)

    describe("/{entity}/{id}", function()
      it("GET", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/some_entities/"..entity_id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("bob", json.name)
        assert.equal(entity_id, json.id)
      end)
      it("PATCH", function()
        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/some_entities/"..entity_id,
          body = {
            name = "updated_bob"
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("updated_bob", json.name)
        assert.equal(entity_id, json.id)
      end)
      it("DELETE", function()
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/some_entities/"..entity_id,
        })
        assert.res_status(204, res)

        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/some_entities/"..entity2_id,
        })
        assert.res_status(204, res)
      end)
      it("GET (should fail)", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/some_entities/"..entity_id
        })
        assert.res_status(404, res)
      end)
    end)

    describe("/{entity}/{secondary_id}", function()
      local entity_id

      setup(function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/some_entities/",
          body = {
            name = "another_bob"
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal("another_bob", json.name)
        entity_id = json.id
      end)

      it("GET", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/some_entities/another_bob"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("another_bob", json.name)
        assert.equal(entity_id, json.id)

        -- But it also works with ID
        local res = assert(admin_client:send {
          method = "GET",
          path = "/some_entities/"..entity_id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("another_bob", json.name)
        assert.equal(entity_id, json.id)
      end)
      it("PATCH", function()
        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/some_entities/another_bob",
          body = {
            name = "updated_bob"
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("updated_bob", json.name)
        assert.equal(entity_id, json.id)
      end)
      it("DELETE", function()
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/some_entities/updated_bob",
        })
        assert.res_status(204, res)
      end)
      
      it("GET (should fail)", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/some_entities/updated_bob"
        })
        assert.res_status(404, res)

        local res = assert(admin_client:send {
          method = "GET",
          path = "/some_entities/another_bob"
        })
        assert.res_status(404, res)

        -- And it also fail with ID
        local res = assert(admin_client:send {
          method = "GET",
          path = "/some_entities/"..entity_id
        })
        assert.res_status(404, res)
      end)
    end)
  end)
end)
