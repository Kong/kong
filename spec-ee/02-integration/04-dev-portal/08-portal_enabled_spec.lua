local helpers      = require "spec.helpers"
local enums       = require "kong.enterprise_edition.dao.enums"
local singletons  = require "kong.singletons"

local tostring = tostring

local function configure_portal(db, ws_on)
  db.workspaces:upsert_by_name("default", {
    name = "default",
    config = {
      portal = ws_on,
      portal_auth = "basic-auth"
    },
  })
end

local function get_expected_status(success, conf_on, ws_on)
  if not conf_on or not ws_on then
    return 404
  end

  return success
end


local function close_clients(clients)
  for idx, client in ipairs(clients) do
    client:close()
  end
end


local function client_request(params)
  local client = assert(helpers.admin_client())
  local res = assert(client:send(params))
  res.body = res.body_reader()

  close_clients({ client })
  return res
end


local configs = {
  {true, false}, -- portal on in conf, off in ws
  {false, true}, -- portal off in conf, on in ws
  {false, false}, -- portal off in both
  {true, true} -- portal on in both
}

for _, strategy in helpers.each_strategy() do
  for _, conf in ipairs(configs) do
    local conf_on = conf[1]
    local ws_on = conf[2]

    describe("Portal Enabled[" .. strategy .. "] conf = " .. tostring(conf_on) .. " ws = " .. tostring(ws_on), function()
      local _, db, _ = helpers.get_db_utils(strategy)
      -- do not run tests for cassandra < 3
      if strategy == "cassandra" and db.connector.major_version < 3 then
        return
      end

      local developer, file

      lazy_setup(function()
        singletons.configuration = {
          database = strategy,
          portal = conf_on,
          portal_auth = "basic-auth",
        }

        assert(helpers.start_kong({
          database = strategy,
          portal = conf_on,
          portal_auth = "basic-auth",
          portal_session_conf = "{ \"secret\": \"super-secret\", \"cookie_secure\": false }",
        }))

        developer = assert(db.developers:insert {
          email = "gruce@konghq.com",
          password = "kong",
          meta = "{\"full_name\":\"I Like Turtles\"}",
          status = enums.CONSUMERS.STATUS.APPROVED,
        })

        file = assert(db.files:insert {
          name = "file",
          contents = "cool",
          type = "page"
        })

        configure_portal(db, ws_on)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        assert(db:truncate())
      end)

      describe("Developers Admin API respects portal enabled configs", function()
        it("/developers", function()
          local res = assert(client_request {
            method = "GET",
            path = "/default/developers"
          })

          local expected_status = get_expected_status(200, conf_on, ws_on)
          assert.res_status(expected_status, res)

          local res = assert(client_request({
            method = "POST",
            path = "/default/developers",
            body = {
              email = "friend@konghq.com",
              password = "wow",
              meta = "{\"full_name\":\"WOW\"}",
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          local expected_status = get_expected_status(200, conf_on, ws_on)
          assert.res_status(expected_status, res)
        end)

        it("/developers/:developers ", function()
          local res = assert(client_request {
            method = "GET",
            path = "/default/developers/" .. developer.id,
          })

          local expected_status = get_expected_status(200, conf_on, ws_on)
          assert.res_status(expected_status, res)
        end)
      end)

      describe("Files Admin API", function()
        it("/files", function()
          local res = assert(client_request {
            method = "GET",
            path = "/default/files"
          })

          local expected_status = get_expected_status(200, conf_on, ws_on)
          assert.res_status(expected_status, res)

          local res = assert(client_request({
            method = "POST",
            path = "/default/files",
            body = {
              name = "fileeeeee",
              contents = "rad",
              type = "page"
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          local expected_status = get_expected_status(201, conf_on, ws_on)
          assert.res_status(expected_status, res)
        end)

        it("/files/:files", function()
          local res = assert(client_request {
            method = "GET",
            path = "/default/files/" .. file.id,
          })

          local expected_status = get_expected_status(200, conf_on, ws_on)
          assert.res_status(expected_status, res)

          local res = assert(client_request({
            method = "PATCH",
            path = "/default/files/" .. file.id,
            body = {
              name = "new_name",
              contents = "new content",
              type = "page"
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          local expected_status = get_expected_status(200, conf_on, ws_on)
          assert.res_status(expected_status, res)
        end)
      end)
    end)
  end
end