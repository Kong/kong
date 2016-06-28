local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("ACL API", function()
  local consumer, admin_client
  setup(function()
    helpers.kill_all()
    assert(helpers.start_kong())
    admin_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.admin_port))
  end)
  teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  describe("/consumers/:consumer/acls/", function()
    setup(function()
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
          assert.equal([[{"group":"group is required"}]], body)
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
          assert.equal([[{"group":"group is required"}]], body)
        end)
      end)
    end)

    describe("GET", function()
      setup(function()
        for i = 1, 3 do
          assert(helpers.dao.acls:insert {
            group = "group"..i,
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
    local acl
    before_each(function()
      helpers.dao:truncate_table("acls")
      acl = assert(helpers.dao.acls:insert {
        group = "hello",
        consumer_id = consumer.id
      })
    end)
    describe("GET", function()
      it("retrieves by id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/acls/"..acl.id
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
          path = "/consumers/bob/acls/"..acl.id
        })
        assert.res_status(200, res)

        res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/alice/acls/"..acl.id
        })
        assert.res_status(404, res)
      end)
    end)

    describe("PATCH", function()
      it("updates an ACL group", function()
        local previous_group = acl.group

        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/consumers/bob/acls/"..acl.id,
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
      describe("errors", function()
        it("handles invalid input", function()
          local res = assert(admin_client:send {
            method = "PATCH",
            path = "/consumers/bob/acls/"..acl.id,
            body = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"group":"ACL group already exist for this consumer"}]], body)
        end)
      end)
    end)

    describe("DELETE", function()
      it("deletes an ACL group", function()
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/bob/acls/"..acl.id,
        })
        assert.res_status(204, res)
      end)
      describe("errors", function()
        it("returns 400 on invalid input", function()
          local res = assert(admin_client:send {
            method = "DELETE",
            path = "/consumers/bob/acls/blah"
          })
          assert.res_status(400, res)
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
