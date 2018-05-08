local helpers = require "spec.helpers"
local cjson = require "cjson"
local enums = require "kong.portal.enums"
local is_valid_uuid = require "kong.tools.utils".is_valid_uuid
local proxy_prefix
              = require "kong.enterprise_edition.proxies".proxy_prefix


local function insert_files(dao)
  for i = 1, 10 do
    assert(dao.portal_files:insert {
      name = "file-" .. i,
      contents = "i-" .. i,
      type = "partial",
      auth = i % 2 == 0 and true or false
    })
  end
end


-- TODO: Cassandra
for _, strategy in helpers.each_strategy('postgres') do

describe("Developer Portal - Portal API", function()
  local bp
  local db
  local dao
  local client
  local consumerApproved

  setup(function()
    bp, db, dao = helpers.get_db_utils(strategy, true)
  end)

  teardown(function()
    helpers.stop_kong(nil, true)
  end)

  describe("/_kong/portal/files without auth", function()
    before_each(function()
      helpers.stop_kong(nil, true)
      --assert(db:truncate())
      helpers.register_consumer_relations(dao)

      assert(helpers.start_kong({
        database   = strategy,
        portal     = true
      }))

      client = assert(helpers.proxy_client())
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("GET", function()
      before_each(function()
        insert_files(dao)
      end)

      teardown(function()
        --db:truncate()
      end)

      it("retrieves files", function()
        local res = assert(client:send {
          method = "GET",
          path = "/" .. proxy_prefix .. "/portal/files",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equal(10, json.total)
        assert.equal(10, #json.data)
      end)

      it("retrieves only unauthenticated files", function()
        local res = assert(client:send {
          method = "GET",
          path = "/" .. proxy_prefix .. "/portal/files/unauthenticated",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equal(5, json.total)
        assert.equal(5, #json.data)
        for key, value in ipairs(json.data) do
          assert.equal(false, value.auth)
        end
      end)
    end)
  end)

  describe("/_kong/portal/files with auth", function()
    setup(function()
      helpers.stop_kong(nil, true)
      --assert(db:truncate())
      helpers.register_consumer_relations(dao)

      insert_files(dao)

      assert(helpers.start_kong({
        database   = strategy,
        portal     = true,
        portal_auth = "basic-auth",
        portal_auth_config = "{ \"hide_credentials\": true }"
      }))

      local consumerPending = bp.consumers:insert {
        username = "dale",
        status = enums.CONSUMERS.TYPE.PENDING
      }

      consumerApproved = bp.consumers:insert {
        username = "hawk",
        status = enums.CONSUMERS.STATUS.APPROVED
      }

      assert(dao.basicauth_credentials:insert {
        username    = "dale",
        password    = "kong",
        consumer_id = consumerPending.id
      })

      assert(dao.basicauth_credentials:insert {
        username    = "hawk",
        password    = "kong",
        consumer_id = consumerApproved.id
      })
    end)

    before_each(function()
      client = assert(helpers.proxy_client())
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("GET", function()
      it("returns 401 when unauthenticated", function()
        local res = assert(client:send {
          method = "GET",
          path = "/" .. proxy_prefix .. "/portal/files",
        })

        assert.res_status(401, res)
      end)

      it("returns 401 when consumer is not approved", function()
        local res = assert(client:send {
          method = "GET",
          path = "/" .. proxy_prefix .. "/portal/files",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("dale:kong"),
          }
        })

        assert.res_status(401, res)
      end)

      it("retrieves files with an approved consumer", function()
        local res = assert(client:send {
          method = "GET",
          path = "/" .. proxy_prefix .. "/portal/files",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equal(10, json.total)
        assert.equal(10, #json.data)
      end)
    end)

    describe("POST, PATCH, PUT", function ()
      it("does not allow forbidden methods", function()
        local consumer_auth_header = "Basic " .. ngx.encode_base64("hawk:kong")

        local res_put = assert(client:send {
          method = "PUT",
          path = "/" .. proxy_prefix .. "/portal/files",
          headers = {
            ["Authorization"] = consumer_auth_header,
          }
        })

        assert.res_status(405, res_put)

        local res_patch = assert(client:send {
          method = "PATCH",
          path = "/" .. proxy_prefix .. "/portal/files",
          headers = {
            ["Authorization"] = consumer_auth_header,
          }
        })

        assert.res_status(405, res_patch)

        local res_post = assert(client:send {
          method = "POST",
          path = "/" .. proxy_prefix .. "/portal/files",
          headers = {
            ["Authorization"] = consumer_auth_header,
          }
        })

        assert.res_status(405, res_post)
      end)
    end)
  end)


  describe("/portal/register", function()
    before_each(function()
      client = assert(helpers.proxy_client())
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("POST", function()
      it("registers a developer and set status to pending", function()
        local res = assert(client:send {
          method = "POST",
          path = "/" .. proxy_prefix .. "/portal/register",
          body = {
            email = "gruce@konghq.com",
            password = "kong"
          },
          headers = {["Content-Type"] = "application/json"}
        })

        local body = assert.res_status(201, res)
        local resp_body_json = cjson.decode(body)

        local credential = resp_body_json.credential
        local consumer = resp_body_json.consumer

        assert.equal("gruce@konghq.com", credential.username)
        assert.is_true(is_valid_uuid(credential.id))
        assert.is_true(is_valid_uuid(consumer.id))

        assert.equal(enums.CONSUMERS.TYPE.DEVELOPER, consumer.type)
        assert.equal(enums.CONSUMERS.STATUS.PENDING, consumer.status)
        assert.equal(enums.CONSUMERS.TYPE.DEVELOPER, consumer.type)

        assert.equal(consumer.id, credential.consumer_id)
      end)
    end)
  end)
end)

end
