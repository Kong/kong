local helpers = require "spec.helpers"
local cjson = require "cjson"
local enums = require "kong.portal.enums"
local utils = require "kong.tools.utils"
local proxy_prefix = require("kong.enterprise_edition.proxies").proxy_prefix


local function insert_files(dao)
  helpers.with_current_ws(nil, function()
  for i = 1, 10 do
    assert(dao.portal_files:insert {
      name = "file-" .. i,
      contents = "i-" .. i,
      type = "partial",
      auth = i % 2 == 0 and true or false
    })
  end
  end, dao)
end


-- TODO: Cassandra
for _, strategy in helpers.each_strategy('postgres') do

pending("Developer Portal - Portal API", function()
  local bp
  local db
  local dao
  local client
  local consumer_approved

  setup(function()
    bp, db, dao = helpers.get_db_utils(strategy)
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  describe("/_kong/portal/files without auth", function()
    before_each(function()
      helpers.stop_kong()
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
        db:truncate()
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
      helpers.stop_kong()
      assert(db:truncate())
      helpers.register_consumer_relations(dao)

      insert_files(dao)

      assert(helpers.start_kong({
        database   = strategy,
        portal     = true,
        portal_auth = "basic-auth",
        portal_auth_config = "{ \"hide_credentials\": true }"
      }))

      helpers.with_current_ws(nil, function()
      local consumer_pending = bp.consumers:insert {
        username = "dale",
        status = enums.CONSUMERS.STATUS.PENDING
      }

      consumer_approved = bp.consumers:insert {
        username = "hawk",
        status = enums.CONSUMERS.STATUS.APPROVED
      }

      assert(dao.basicauth_credentials:insert {
        username    = "dale",
        password    = "kong",
        consumer_id = consumer_pending.id
      })

      assert(dao.basicauth_credentials:insert {
        username    = "hawk",
        password    = "kong",
        consumer_id = consumer_approved.id
      })
      end, dao)
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

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ status = 1, label = "PENDING" }, json)
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
        assert.is_true(utils.is_valid_uuid(credential.id))
        assert.is_true(utils.is_valid_uuid(consumer.id))

        assert.equal(enums.CONSUMERS.TYPE.DEVELOPER, consumer.type)
        assert.equal(enums.CONSUMERS.STATUS.PENDING, consumer.status)
        assert.equal(enums.CONSUMERS.TYPE.DEVELOPER, consumer.type)

        assert.equal(consumer.id, credential.consumer_id)
      end)
    end)
  end)

  describe("/credentials", function()
    local credential

    before_each(function()
      client = assert(helpers.proxy_client())
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("POST", function()
      it("adds a credential to a developer - basic-auth", function()
        local res = assert(client:send {
          method = "POST",
          path = "/" .. proxy_prefix .. "/portal/credentials",
          body = {
            username = "kong",
            password = "hunter1"
          },
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
          }
        })

        local body = assert.res_status(201, res)
        local resp_body_json = cjson.decode(body)

        credential = resp_body_json

        assert.equal("kong", credential.username)
        assert.are_not.equals("hunter1", credential.password)
        assert.is_true(utils.is_valid_uuid(credential.id))
      end)
    end)

    describe("PATCH", function()
      it("patches a credential - basic-auth", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/" .. proxy_prefix .. "/portal/credentials",
          body = {
            id = credential.id,
            username = "anotherone",
            password = "another-hunter1"
          },
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)
        local credential_res = resp_body_json

        assert.equal("anotherone", credential_res.username)
        assert.are_not.equals(credential_res.username, credential.username)
        assert.are_not.equals("another-hunter1", credential_res.password)
        assert.is_true(utils.is_valid_uuid(credential_res.id))
      end)
    end)
  end)

  describe("/credentials/:plugin", function()
    local credential
    local credential_key_auth

    before_each(function()
      client = assert(helpers.proxy_client())
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)


    describe("POST", function()
      it("adds auth plugin credential - basic-auth", function()
        local plugin = "basic-auth"

        local res = assert(client:send {
          method = "POST",
          path = "/" .. proxy_prefix .. "/portal/credentials/" .. plugin,
          body = {
            username = "dude",
            password = "hunter1"
          },
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
          }
        })

        local body = assert.res_status(201, res)
        local resp_body_json = cjson.decode(body)

        credential = resp_body_json

        assert.equal("dude", credential.username)
        assert.are_not.equals("hunter1", credential.password)
        assert.is_true(utils.is_valid_uuid(credential.id))
      end)

      it("adds auth plugin credential - key-auth", function()
        local plugin = "key-auth"

        local res = assert(client:send {
          method = "POST",
          path = "/" .. proxy_prefix .. "/portal/credentials/" .. plugin,
          body = {
            key = "letmein"
          },
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
          }
        })

        local body = assert.res_status(201, res)
        local resp_body_json = cjson.decode(body)

        credential_key_auth = resp_body_json

        assert.equal("letmein", credential_key_auth.key)
        assert.is_true(utils.is_valid_uuid(credential_key_auth.id))
      end)
    end)

    describe("GET", function()
      it("retrieves a credential - basic-auth", function()
        local plugin = "basic-auth"
        local path = "/" .. proxy_prefix .. "/portal/credentials/"
                      .. plugin .. "/" .. credential.id

        local res = assert(client:send {
          method = "GET",
          path = path,
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)
        local credential_res = resp_body_json

        assert.equal(credential.username, credential_res.username)
        assert.equal(credential.id, credential_res.id)
      end)
    end)

    describe("PATCH", function()
      it("/portal/credentials/:plugin/ - basic-auth", function()
        local plugin = "basic-auth"
        local path = "/" .. proxy_prefix .. "/portal/credentials/"
                       .. plugin .. "/" .. credential.id

        local res = assert(client:send {
          method = "PATCH",
          path = path,
          body = {
            id = credential.id,
            username = "dudett",
            password = "a-new-password"
          },
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)
        local credential_res = resp_body_json

        assert.equal("dudett", credential_res.username)
        assert.are_not.equals("a-new-password", credential_res.password)
        assert.is_true(utils.is_valid_uuid(credential_res.id))

        assert.are_not.equals(credential_res.username, credential.username)
      end)

      it("/portal/credentials/:plugin/:credential_id - basic-auth", function()
        local plugin = "basic-auth"
        local path = "/" .. proxy_prefix .. "/portal/credentials/"
                       .. plugin .. "/" .. credential.id

        local res = assert(client:send {
          method = "PATCH",
          path = path,
          body = {
            username = "duderino",
            password = "a-new-new-password"
          },
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)
        local credential_res = resp_body_json

        assert.equal("duderino", credential_res.username)
        assert.are_not.equals("a-new-new-password", credential_res.password)
        assert.is_true(utils.is_valid_uuid(credential_res.id))

        assert.are_not.equals(credential_res.username, credential.username)
      end)
    end)

    describe("DELETE", function()
      it("deletes a credential", function()
        local plugin = "key-auth"
        local path = "/" .. proxy_prefix .. "/portal/credentials/"
                       .. plugin .. "/" .. credential_key_auth.id

        local res = assert(client:send {
          method = "DELETE",
          path = path,
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
          }
        })

        assert.res_status(204, res)

        local res = assert(client:send {
          method = "GET",
          path = path,
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
          }
        })

        assert.res_status(404, res)
      end)
    end)

    describe("GET", function()
      it("retrieves the kong config tailored for the dev portal", function()
        local res = assert(client:send {
          method = "GET",
          path = "/" .. proxy_prefix .. "/portal/config",
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        local config = resp_body_json

        assert.same({ "cors", "basic-auth" }, config.plugins.enabled_in_cluster)
      end)
    end)
  end)
end)

end

pending("portal dao_helpers", function()
  local dao

  setup(function()
    dao = select(3, helpers.get_db_utils("cassandra"))

    local cassandra = require "kong.dao.db.cassandra"
    local dao_cassandra = cassandra.new(helpers.test_conf)

    -- raw cassandra insert without dao so "type" is nil
    for i = 1, 10 do
      local query = string.format([[INSERT INTO %s.consumers
                                                (id, custom_id)
                                                VALUES(%s, '%s')]],
                                  helpers.test_conf.cassandra_keyspace,
                                  utils.uuid(),
                                  "cassy-" .. i)
      dao_cassandra:query(query)
    end

    local rows = dao.consumers:find_all()

    assert.equals(10, #rows)
    for _, row in ipairs(rows) do
      assert.is_nil(row.type)
    end

  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("updates consumers with nil type to default proxy type", function()
    local portal = require "kong.portal.dao_helpers"
    portal.update_consumers(dao, enums.CONSUMERS.TYPE.PROXY)

    local rows = dao.consumers:find_all()
    for _, row in ipairs(rows) do
      assert.equals(enums.CONSUMERS.TYPE.PROXY, row.type)
    end
    assert.equals(10, #rows)
  end)
end)
