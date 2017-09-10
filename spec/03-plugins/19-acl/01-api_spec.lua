local cjson = require "cjson"
local helpers = require "spec.helpers"

describe("Plugin: acl (API)", function()
  local consumer, admin_client
  setup(function()
    helpers.run_migrations()

    assert(helpers.start_kong())
    admin_client = helpers.admin_client()
  end)
  teardown(function()
    if admin_client then admin_client:close() end
    helpers.stop_kong()
  end)

  describe("/consumers/:consumer/acls/", function()
    setup(function()
      helpers.dao:truncate_tables()
      consumer = assert(helpers.dao.consumers:insert {
        username = "bob"
      })
    end)
    after_each(function()
      helpers.dao:truncate_table("acls")
    end)

    describe("POST", function()
      it("creates an ACL association", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/acls",
          body = {
            group = "admin"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal(consumer.id, json.consumer_id)
        assert.equal("admin", json.group)
      end)
      describe("errors", function()
        it("returns bad request", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/consumers/bob/acls",
            body = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ group = "group is required" }, json)
        end)
      end)
    end)

    describe("PUT", function()
      it("creates a basic-auth credential", function()
        local res = assert(admin_client:send {
          method = "PUT",
          path = "/consumers/bob/acls",
          body = {
            group = "pro"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal(consumer.id, json.consumer_id)
        assert.equal("pro", json.group)
      end)
      describe("errors", function()
        it("returns bad request", function()
          local res = assert(admin_client:send {
          method = "PUT",
          path = "/consumers/bob/acls",
          body = {},
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ group = "group is required" }, json)
        end)
      end)
    end)

    describe("GET", function()
      setup(function()
        for i = 1, 3 do
          assert(helpers.dao.acls:insert {
            group = "group" .. i,
            consumer_id = consumer.id
          })
        end
      end)
      teardown(function()
        helpers.dao:truncate_table("acls")
      end)
      it("retrieves the first page", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/acls"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(3, #json.data)
        assert.equal(3, json.total)
      end)
    end)
  end)

  describe("/consumers/:consumer/acls/:id", function()
    local acl, acl2
    before_each(function()
      helpers.dao:truncate_table("acls")
      acl = assert(helpers.dao.acls:insert {
        group = "hello",
        consumer_id = consumer.id
      })
      acl2 = assert(helpers.dao.acls:insert {
        group = "hello2",
        consumer_id = consumer.id
      })
    end)
    describe("GET", function()
      it("retrieves by id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/acls/" .. acl.id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(acl.id, json.id)
      end)
      it("retrieves by group", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/acls/" .. acl.group
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(acl.id, json.id)
      end)
      it("retrieves ACL by id only if the ACL belongs to the specified consumer", function()
        assert(helpers.dao.consumers:insert {
          username = "alice"
        })

        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/acls/" .. acl.id
        })
        assert.res_status(200, res)

        res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/alice/acls/" .. acl.id
        })
        assert.res_status(404, res)
      end)
      it("retrieves ACL by group only if the ACL belongs to the specified consumer", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/acls/" .. acl.group
        })
        assert.res_status(200, res)

        res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/alice/acls/" .. acl.group
        })
        assert.res_status(404, res)
      end)
    end)

    describe("PATCH", function()
      it("updates an ACL group by id", function()
        local previous_group = acl.group

        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/consumers/bob/acls/" .. acl.id,
          body = {
            group = "updatedGroup"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.not_equal(previous_group, json.group)
      end)
      it("updates an ACL group by group", function()
        local previous_group = acl.group

        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/consumers/bob/acls/" .. acl.group,
          body = {
            group = "updatedGroup2"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.not_equal(previous_group, json.group)
      end)
      describe("errors", function()
        it("handles invalid input", function()
          local res = assert(admin_client:send {
            method = "PATCH",
            path = "/consumers/bob/acls/" .. acl.id,
            body = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ group = "ACL group already exist for this consumer" }, json)
        end)
      end)
    end)

    describe("DELETE", function()
      it("deletes an ACL group by id", function()
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/bob/acls/" .. acl.id,
        })
        assert.res_status(204, res)
      end)
      it("deletes an ACL group by group", function()
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/bob/acls/" .. acl2.group,
        })
        assert.res_status(204, res)
      end)
      describe("errors", function()
        it("returns 404 on missing group", function()
          local res = assert(admin_client:send {
            method = "DELETE",
            path = "/consumers/bob/acls/blah"
          })
          assert.res_status(404, res)
        end)
        it("returns 404 if not found", function()
          local res = assert(admin_client:send {
            method = "DELETE",
            path = "/consumers/bob/acls/00000000-0000-0000-0000-000000000000"
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)
end)
