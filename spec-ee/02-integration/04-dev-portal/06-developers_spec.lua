-- local helpers    = require "spec.helpers"
-- local ee_helpers = require "spec-ee.helpers"
-- local cjson      = require "cjson"
-- local enums      = require "kong.enterprise_edition.dao.enums"

-- local function configure_portal(dao)
--   local workspaces = dao.workspaces:find_all({name = "default"})
--   local workspace = workspaces[1]

--   dao.workspaces:update({
--     config = {
--       portal = true,
--     }
--   }, {
--     id = workspace.id,
--   })
-- end

-- for _, strategy in helpers.each_strategy() do

-- describe("Admin API - Developer Portal - " .. strategy, function()
--   local client
--   local portal_api_client
--   local db
--   local dao

--   setup(function()
--     _, db, dao = helpers.get_db_utils(strategy)

--     assert(helpers.start_kong({
--       portal = true,
--       database = strategy,
--     }))
--   end)

--   teardown(function()
--     helpers.stop_kong()
--   end)

--   before_each(function()
--     configure_portal(dao)
--   end)

--   after_each(function()
--     if client then client:close() end
--     if portal_api_client then portal_api_client:close() end
--   end)

--   describe("/portal/developers", function()
--     describe("GET", function ()

--       before_each(function()
--         local portal = require "kong.portal.dao_helpers"
--         dao:truncate_tables()

--         portal.register_resources(dao)

--         for i = 1, 5 do
--           assert(dao.consumers:insert {
--             username = "developer-consumer-" .. i,
--             custom_id = "developer-consumer-" .. i,
--             type = enums.CONSUMERS.TYPE.DEVELOPER
--           })
--         end

--         configure_portal(dao)
--       end)

--       teardown(function()
--         dao:truncate_tables()
--       end)

--       it("retrieves list of developers only", function()
--         local res = assert(client:send {
--           methd = "GET",
--           path = "/portal/developers"
--         })
--         res = assert.res_status(200, res)
--         local json = cjson.decode(res)
--         assert.equal(5, #json.data)
--       end)

--       it("cannot retrieve proxy consumers", function()
--         local res = assert(client:send {
--           methd = "GET",
--           path = "/portal/developers?type=0"
--         })
--         res = assert.res_status(400, res)
--         local json = cjson.decode(res)
--         assert.same({ message = "type is invalid" }, json)
--       end)

--       it("filters by developer status", function()
--         assert(dao.consumers:insert {
--           username = "developer-pending",
--           custom_id = "developer-pending",
--           type = enums.CONSUMERS.TYPE.DEVELOPER,
--           status = enums.CONSUMERS.STATUS.PENDING
--         })

--         local res = assert(client:send {
--           methd = "GET",
--           path = "/portal/developers/?status=1"
--         })
--         res = assert.res_status(200, res)
--         local json = cjson.decode(res)
--         assert.equal(1, #json.data)
--       end)
--     end)
--   end)

--   describe("/portal/developers/:email_or_id", function()
--     local developer
--     before_each(function()
--       helpers.stop_kong()
--       assert(db:truncate())
--       helpers.register_consumer_relations(dao)

--       assert(helpers.start_kong({
--         database   = strategy,
--         portal     = true,
--         portal_auth = "basic-auth",
--         portal_auth_config = "{ \"hide_credentials\": true }",
--         portal_auto_approve = "off",
--         portal_session_conf = "{ \"cookie_name\": \"portal_session\", \"secret\": \"super-secret\", \"cookie_secure\": false, \"storage\": \"kong\" }",
--         admin_gui_url = "http://localhost:8080",
--       }))

--       portal_api_client = assert(ee_helpers.portal_api_client())
--       client = assert(helpers.admin_client())
--       configure_portal(dao)

--       local res = assert(portal_api_client:send {
--         method = "POST",
--         path = "/register",
--         body = {
--           email = "gruce@konghq.com",
--           password = "kong",
--           meta = "{\"full_name\":\"I Like Turtles\"}"
--         },
--         headers = {["Content-Type"] = "application/json"}
--       })

--       local body = assert.res_status(201, res)
--       local resp_body_json = cjson.decode(body)
--       developer = resp_body_json.consumer
--     end)

--     describe("GET", function()
--       it("fetches the developer", function()
--         local res = assert(client:send {
--           method = "GET",
--           path = "/portal/developers/".. developer.id,
--         })

--         local body = assert.res_status(200, res)
--         local resp_body_json = cjson.decode(body)

--         assert.same(developer, resp_body_json)
--       end)
--     end)

--     describe("PATCH", function()
--       describe("smtp = on", function()
--         it("it rejects a type other than DEVELOPER", function()
--           local res = assert(client:send {
--             method = "PATCH",
--             body = {
--               type = enums.CONSUMERS.TYPE.ADMIN
--             },
--             path = "/portal/developers/".. developer.id,
--             headers = {["Content-Type"] = "application/json"}
--           })

--           local body = assert.res_status(400, res)
--           local resp_body_json = cjson.decode(body)
--           local message = resp_body_json.message

--           assert.equal("type is invalid", message)

--           local res = assert(client:send {
--             method = "PATCH",
--             body = {
--               type = enums.CONSUMERS.TYPE.PROXY
--             },
--             path = "/portal/developers/".. developer.id,
--             headers = {["Content-Type"] = "application/json"}
--           })

--           local body = assert.res_status(400, res)
--           local resp_body_json = cjson.decode(body)
--           local message = resp_body_json.message

--           assert.equal("type is invalid", message)

--           local res = assert(client:send {
--             method = "PATCH",
--             body = {
--               type = enums.CONSUMERS.TYPE.DEVELOPER
--             },
--             path = "/portal/developers/".. developer.id,
--             headers = {["Content-Type"] = "application/json"}
--           })

--           local body = assert.res_status(200, res)
--           local resp_body_json = cjson.decode(body)

--           assert.same(developer, resp_body_json.consumer)
--         end)

--         it("sends an email to the approved developer", function()
--           local res = assert(client:send {
--             method = "PATCH",
--             body = {
--               status = 0
--             },
--             path = "/portal/developers/".. developer.id,
--             headers = {["Content-Type"] = "application/json"}
--           })

--           local expected_email = {
--             error = {
--               count = 0,
--               emails = {},
--             },
--             sent = {
--               count = 1,
--               emails = {
--                 ["gruce@konghq.com"] = true,
--               }
--             },
--             smtp_mock = true,
--           }

--           local body = assert.res_status(200, res)
--           local resp_body_json = cjson.decode(body)
--           assert.same(expected_email, resp_body_json.email)
--         end)

--         it("does not send an email if rejected, revoked, or re-approved from revoked", function()
--           local res = assert(client:send {
--             method = "PATCH",
--             body = {
--               status = 2
--             },
--             path = "/portal/developers/".. developer.id,
--             headers = {["Content-Type"] = "application/json"}
--           })

--           local body = assert.res_status(200, res)
--           local resp_body_json = cjson.decode(body)
--           assert.is_nil(resp_body_json.email)

--           local res = assert(client:send {
--             method = "PATCH",
--             body = {
--               status = 3
--             },
--             path = "/portal/developers/".. developer.id,
--             headers = {["Content-Type"] = "application/json"}
--           })

--           local body = assert.res_status(200, res)
--           local resp_body_json = cjson.decode(body)
--           assert.is_nil(resp_body_json.email)

--           local res = assert(client:send {
--             method = "PATCH",
--             body = {
--               status = 0
--             },
--             path = "/portal/developers/".. developer.id,
--             headers = {["Content-Type"] = "application/json"}
--           })

--           local body = assert.res_status(200, res)
--           local resp_body_json = cjson.decode(body)
--           assert.is_nil(resp_body_json.email)
--         end)

--         it("updates the developer email, username, and login credential", function()
--           local res = assert(client:send {
--             method = "PATCH",
--             body = {
--               email = "new_email@whodis.com",
--               status = 0,
--             },
--             path = "/portal/developers/".. developer.id,
--             headers = {
--               ["Content-Type"] = "application/json",
--             }
--           })

--           local body = assert.res_status(200, res)
--           local resp_body_json = cjson.decode(body)
--           assert.equals("new_email@whodis.com", resp_body_json.consumer.email)
--           assert.equals("new_email@whodis.com", resp_body_json.consumer.username)

--           -- old email fails to access portal api
--           local res = assert(portal_api_client:send {
--             method = "GET",
--             path = "/auth",
--             headers = {
--               ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
--             }
--           })

--           local body = assert.res_status(403, res)
--           local json = cjson.decode(body)
--           assert.equals("Invalid authentication credentials", json.message)

--           local cookie = res.headers["Set-Cookie"]
--           assert.is_nil(cookie)

--           -- new email succeeds to access portal api
--           local res = assert(portal_api_client:send {
--             method = "GET",
--             path = "/auth",
--             headers = {
--               ["Authorization"] = "Basic " .. ngx.encode_base64("new_email@whodis.com:kong"),
--             }
--           })

--           assert.res_status(200, res)
--           cookie = assert.response(res).has.header("Set-Cookie")

--           local res = assert(portal_api_client:send {
--             method = "GET",
--             path = "/developer",
--             headers = {
--               ["Cookie"] = cookie
--             },
--           })

--           local body = assert.res_status(200, res)
--           local resp_body_json = cjson.decode(body)
--           assert.equal("new_email@whodis.com", resp_body_json.email)
--           assert.equal("new_email@whodis.com", resp_body_json.username)
--         end)

--         it("returns 400 if patched with an invalid email", function()
--           local res = assert(client:send {
--             method = "PATCH",
--             body = {
--               email = "emailol.com",
--             },
--             path = "/portal/developers/".. developer.id,
--             headers = {
--               ["Content-Type"] = "application/json",
--             }
--           })

--           local body = assert.res_status(400, res)
--           local resp_body_json = cjson.decode(body)
--           local message = resp_body_json.message

--           assert.equal("Invalid email: missing '@' symbol", message)
--         end)

--         it("returns 409 if patched with an email that already exists", function()

--           local res = assert(portal_api_client:send {
--             method = "POST",
--             path = "/register",
--             body = {
--               email = "fancypants@konghq.com",
--               password = "mowmow",
--               meta = "{\"full_name\":\"Old Gregg\"}"
--             },
--             headers = {["Content-Type"] = "application/json"}
--           })

--           local body = assert.res_status(201, res)
--           local resp_body_json = cjson.decode(body)
--           local developer2 = resp_body_json.consumer

--           local res = assert(client:send {
--             method = "PATCH",
--             body = {
--               email = developer2.email,
--             },
--             path = "/portal/developers/".. developer.id,
--             headers = {
--               ["Content-Type"] = "application/json",
--             }
--           })

--           local body = assert.res_status(409, res)
--           local resp_body_json = cjson.decode(body)
--           local message = resp_body_json.username

--           assert.equal("already exists with value 'fancypants@konghq.com'", message)
--         end)
--       end)
--     end)
--   end)

--   describe("/portal/invite", function()
--     describe("POST", function()
--       describe("portal_invite_email = off", function()
--         before_each(function()
--           helpers.stop_kong()
--           assert(db:truncate())
--           helpers.register_consumer_relations(dao)

--           assert(helpers.start_kong({
--             database   = strategy,
--             portal     = true,
--             portal_auth = "basic-auth",
--             portal_auth_config = "{ \"hide_credentials\": true }",
--             portal_auto_approve = "off",
--             portal_invite_email = "off",
--           }))

--           client = assert(helpers.admin_client())
--           configure_portal(dao)
--         end)

--         it("returns 501 if portal_invite_email is turned off", function()
--           local res = assert(client:send {
--             method = "POST",
--             body = {
--               emails = {"me@example.com"},
--             },
--             path = "/portal/invite",
--             headers = {
--               ["Content-Type"] = "application/json",
--             }
--           })

--           local body = assert.res_status(501, res)
--           local resp_body_json = cjson.decode(body)
--           local message = resp_body_json.message

--           assert.equal("portal_invite_email is disabled", message)
--         end)
--       end)

--       describe("smtp = on, valid config", function()
--         before_each(function()
--           helpers.stop_kong()
--           assert(db:truncate())
--           helpers.register_consumer_relations(dao)

--           assert(helpers.start_kong({
--             database   = strategy,
--             portal     = true,
--             portal_auth = "basic-auth",
--             portal_auth_config = "{ \"hide_credentials\": true }",
--             portal_auto_approve = "off",
--             portal_emails_from = "me@example.com",
--             portal_emails_reply_to = "me@example.com",
--             smtp = "on",
--             smtp_mock = "on",
--           }))

--           client = assert(helpers.admin_client())
--           configure_portal(dao)
--         end)

--         it("returns 400 if not sent with emails param", function()
--           local res = assert(client:send {
--             method = "POST",
--             body = {

--             },
--             path = "/portal/invite",
--             headers = {
--               ["Content-Type"] = "application/json",
--             }
--           })

--           local body = assert.res_status(400, res)
--           local resp_body_json = cjson.decode(body)
--           local message = resp_body_json.message

--           assert.equal("emails param required", message)
--         end)

--         it("returns 400 if emails is empty", function()
--           local res = assert(client:send {
--             method = "POST",
--             body = {
--               emails = {},
--             },
--             path = "/portal/invite",
--             headers = {
--               ["Content-Type"] = "application/json",
--             }
--           })

--           local body = assert.res_status(400, res)
--           local resp_body_json = cjson.decode(body)
--           local message = resp_body_json.message

--           assert.equal("emails param required", message)
--         end)

--         it("returns 200 if emails are sent", function()
--           local res = assert(client:send {
--             method = "POST",
--             body = {
--               emails = {"me@example.com", "you@example.com"},
--             },
--             path = "/portal/invite",
--             headers = {
--               ["Content-Type"] = "application/json",
--             }
--           })

--           local expected = {
--             smtp_mock = true,
--             error = {
--               count = 0,
--               emails = {},
--             },
--             sent = {
--               count = 2,
--               emails = {
--                 ["me@example.com"] = true,
--                 ["you@example.com"] = true,
--               },
--             }
--           }

--           local body = assert.res_status(200, res)
--           local resp_body_json = cjson.decode(body)

--           assert.same(expected, resp_body_json)
--         end)

--         it("returns 200 if some of the emails are sent", function()
--           local res = assert(client:send {
--             method = "POST",
--             body = {
--               emails = {"me@example.com", "bademail.com"},
--             },
--             path = "/portal/invite",
--             headers = {
--               ["Content-Type"] = "application/json",
--             }
--           })

--           local expected = {
--             smtp_mock = true,
--             error = {
--               count = 1,
--               emails = {
--                 ["bademail.com"] = "Invalid email: missing '@' symbol",
--               },
--             },
--             sent = {
--               count = 1,
--               emails = {
--                 ["me@example.com"] = true,
--               },
--             }
--           }

--           local body = assert.res_status(200, res)
--           local resp_body_json = cjson.decode(body)

--           assert.same(expected, resp_body_json)
--         end)

--         it("returns 400 if none of the emails are sent", function()
--           local res = assert(client:send {
--             method = "POST",
--             body = {
--               emails = {"notemail", "bademail.com"},
--             },
--             path = "/portal/invite",
--             headers = {
--               ["Content-Type"] = "application/json",
--             }
--           })

--           local expected = {
--             smtp_mock = true,
--             error = {
--               count = 2,
--               emails = {
--                 ["notemail"] = "Invalid email: missing '@' symbol",
--                 ["bademail.com"] = "Invalid email: missing '@' symbol",
--               },
--             },
--             sent = {
--               count = 0,
--               emails = {},
--             }
--           }

--           local body = assert.res_status(400, res)
--           local resp_body_json = cjson.decode(body)

--           assert.same(expected, resp_body_json.message)
--         end)
--       end)
--     end)
--   end)
-- end)
-- end
