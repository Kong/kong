local cjson   = require "cjson"
local helpers = require "spec.helpers"
local singletons  = require "kong.singletons"
local enums       = require "kong.enterprise_edition.dao.enums"
local ee_helpers  = require "spec-ee.helpers"


local function configure_portal()
  singletons.db.workspaces:upsert_by_name("default", {
    name = "default",
    config = {
      portal = true,
      portal_auth = "basic-auth",
    }
  })
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


for _, strategy in helpers.each_strategy() do

describe("Admin API - Developer Portal - " .. strategy, function()
  local client, portal_api_client
  local db, dao

  _, db, dao = helpers.get_db_utils(strategy)
  -- do not run tests for cassandra < 3
  if strategy == "cassandra" and db.connector.major_version < 3 then
    return
  end

  lazy_setup(function()
    singletons.configuration = {
      portal_auth = "basic-auth",
    }

    assert(helpers.start_kong({
      portal = true,
      portal_auth = "basic-auth",
      database = strategy,
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.admin_client()
    portal_api_client = ee_helpers.portal_api_client()
    configure_portal(db)
  end)

  after_each(function()
    if client then client:close() end
    if portal_api_client then portal_api_client:close() end
  end)

  describe("/developers", function()
    describe("GET", function ()
      lazy_setup(function()
        for i = 1, 5 do
          assert(db.developers:insert {
            email = "developer-" .. i .. "@dog.com"
          })
        end
        configure_portal()
      end)

      lazy_teardown(function()
        assert(db:truncate())
      end)

      it("retrieves list of developers only", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/developers"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(5, #json.data)
      end)

      it("filters by developer status", function()
        assert(db.developers:insert {
          email = "developer-pending@dog.com",
          status = enums.CONSUMERS.STATUS.PENDING
        })

        local res = assert(client:send {
          method = "GET",
          path = "/developers?status=" .. enums.CONSUMERS.STATUS.PENDING
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(1, #json.data)
      end)

      it("paginates correctly", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/developers?size=3"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(3, #json.data)

        local next = json.next
        local res = assert(client:send {
          methd = "GET",
          path = next
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(3, #json.data)
        assert.equal(ngx.null, json.next)
      end)
    end)

    describe("POST", function ()
      -- XXX DEVX: write post tests
    end)
  end)

  describe("/developers/:developers", function()
    local developer

    lazy_setup(function()
      developer = assert(db.developers:insert {
        email = "gruce@konghq.com",
        password = "kong",
        meta = "{\"full_name\":\"I Like Turtles\"}",
        status = enums.CONSUMERS.STATUS.REJECTED,
      })
      configure_portal()
    end)

    lazy_teardown(function()
      assert(db:truncate())
    end)

    describe("GET", function()
      it("fetches the developer", function()
        local res = assert(client:send {
          method = "GET",
          path = "/developers/".. developer.id,
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        assert.same(developer, resp_body_json)
      end)
    end)

    describe("PATCH", function()
      after_each(function()
        assert(db.developers:update(
          { id = developer.id },
          { email = "gruce@konghq.com", }
        ))
      end)

      it("updates the developer email, username, and login credential", function()
        local res = assert(client:send {
          method = "PATCH",
          body = {
            email = "new_email@whodis.com",
            status = enums.CONSUMERS.STATUS.APPROVED,
          },
          path = "/developers/".. developer.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        local consumer = singletons.db.consumers:select({
          id = resp_body_json.developer.consumer.id
        })

        assert.equals("new_email@whodis.com", resp_body_json.developer.email)
        assert.equals("new_email@whodis.com", consumer.username)

        -- old email fails to access portal api
        local res = assert(portal_api_client:send {
          method = "GET",
          path = "/auth",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
          }
        })

        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.equals("Invalid authentication credentials", json.message)

        local cookie = res.headers["Set-Cookie"]
        assert.is_nil(cookie)

        -- new email succeeds to access portal api
        local res = assert(portal_api_client:send {
          method = "GET",
          path = "/auth",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("new_email@whodis.com:kong"),
          }
        })

        assert.res_status(200, res)
        cookie = assert.response(res).has.header("Set-Cookie")

        local res = assert(portal_api_client:send {
          method = "GET",
          path = "/developer",
          headers = {
            ["Cookie"] = cookie
          },
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)
        assert.equal("new_email@whodis.com", resp_body_json.email)
      end)

      it("returns 400 if patched with an invalid email", function()
        local res = assert(client:send {
          method = "PATCH",
          body = {
            email = "emailol.com",
          },
          path = "/developers/".. developer.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(400, res)
        local resp_body_json = cjson.decode(body)
        local fields = resp_body_json.fields

        assert.equal("missing '@' symbol", fields.email)
      end)

      it("returns 409 if patched with an email that already exists", function()

        local developer2 = assert(db.developers:insert {
          email = "fancypants@konghq.com",
          password = "mowmow",
          meta = "{\"full_name\":\"Old Gregg\"}"
        })

        local res = assert(client:send {
          method = "PATCH",
          body = {
            email = developer2.email,
          },
          path = "/developers/".. developer.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(409, res)
        local resp_body_json = cjson.decode(body)
        local fields = resp_body_json.fields

        assert.equal("already exists with value 'fancypants@konghq.com'", fields.email)
      end)

      describe("smtp", function()

        it("sends an email to the approved developer if their status changes to approved", function()
          -- set to pending first
          local res = assert(client:send {
            method = "PATCH",
            body = {
              status = enums.CONSUMERS.STATUS.PENDING,
            },
            path = "/developers/".. developer.id,
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(200, res)

          local res = assert(client:send {
            method = "PATCH",
            body = {
              status = enums.CONSUMERS.STATUS.APPROVED,
            },
            path = "/developers/".. developer.id,
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local expected_email = {
            error = {
              count = 0,
              emails = {},
            },
            sent = {
              count = 1,
              emails = {
                ["gruce@konghq.com"] = true,
              }
            },
            smtp_mock = true,
          }

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.same(expected_email, resp_body_json.email)
        end)

        it("does not send an email if rejected, revoked, or re-approved from revoked", function()
          local res = assert(client:send {
            method = "PATCH",
            body = {
              status = enums.CONSUMERS.STATUS.REJECTED
            },
            path = "/developers/".. developer.id,
            headers = {["Content-Type"] = "application/json"}
          })

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)
          assert.is_nil(resp_body_json.email)

          local res = assert(client:send {
            method = "PATCH",
            body = {
              status = enums.CONSUMERS.STATUS.REVOKED
            },
            path = "/developers/".. developer.id,
            headers = {["Content-Type"] = "application/json"}
          })

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)
          assert.is_nil(resp_body_json.email)

          local res = assert(client:send {
            method = "PATCH",
            body = {
              status = enums.CONSUMERS.STATUS.APPROVED
            },
            path = "/developers/".. developer.id,
            headers = {["Content-Type"] = "application/json"}
          })

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)
          assert.is_nil(resp_body_json.email)
        end)
      end)
    end)

    -- TODO DEVX: write developer plugin tests
    describe("/developer/:developer/plugins", function()
    end)

    describe("/developer/:developer/plugins/:id", function()
    end)
  end)

  describe("/developers/invite", function()
    describe("POST", function()
      describe("portal_invite_email = off", function()
        before_each(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            portal_auth = "basic-auth",
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "off",
            portal_invite_email = "off",
          }))

          client = assert(helpers.admin_client())
          configure_portal(dao)
        end)

        it("returns 501 if portal_invite_email is turned off", function()
          local res = assert(client:send {
            method = "POST",
            body = {
              emails = {"me@example.com"},
            },
            path = "/developers/invite",
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(501, res)
          local resp_body_json = cjson.decode(body)
          local message = resp_body_json.message

          assert.equal("portal_invite_email is disabled", message)
        end)
      end)

      describe("smtp = on, valid config", function()
        before_each(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            portal_auth = "basic-auth",
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "off",
            portal_emails_from = "me@example.com",
            portal_emails_reply_to = "me@example.com",
            smtp = "on",
            smtp_mock = "on",
          }))

          client = assert(helpers.admin_client())
          configure_portal(dao)
        end)

        it("returns 400 if not sent with emails param", function()
          local res = assert(client:send {
            method = "POST",
            body = {

            },
            path = "/developers/invite",
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(400, res)
          local resp_body_json = cjson.decode(body)
          local message = resp_body_json.message

          assert.equal("emails param required", message)
        end)

        it("returns 400 if emails is empty", function()
          local res = assert(client:send {
            method = "POST",
            body = {
              emails = {},
            },
            path = "/developers/invite",
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(400, res)
          local resp_body_json = cjson.decode(body)
          local message = resp_body_json.message

          assert.equal("emails param required", message)
        end)

        it("returns 200 if emails are sent", function()
          local res = assert(client:send {
            method = "POST",
            body = {
              emails = {"me@example.com", "you@example.com"},
            },
            path = "/developers/invite",
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local expected = {
            smtp_mock = true,
            error = {
              count = 0,
              emails = {},
            },
            sent = {
              count = 2,
              emails = {
                ["me@example.com"] = true,
                ["you@example.com"] = true,
              },
            }
          }

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.same(expected, resp_body_json)
        end)

        it("returns 200 if some of the emails are sent", function()
          local res = assert(client:send {
            method = "POST",
            body = {
              emails = {"me@example.com", "bademail.com"},
            },
            path = "/developers/invite",
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local expected = {
            smtp_mock = true,
            error = {
              count = 1,
              emails = {
                ["bademail.com"] = "Invalid email: missing '@' symbol",
              },
            },
            sent = {
              count = 1,
              emails = {
                ["me@example.com"] = true,
              },
            }
          }

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.same(expected, resp_body_json)
        end)

        it("returns 400 if none of the emails are sent", function()
          local res = assert(client:send {
            method = "POST",
            body = {
              emails = {"notemail", "bademail.com"},
            },
            path = "/developers/invite",
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local expected = {
            smtp_mock = true,
            error = {
              count = 2,
              emails = {
                ["notemail"] = "Invalid email: missing '@' symbol",
                ["bademail.com"] = "Invalid email: missing '@' symbol",
              },
            },
            sent = {
              count = 0,
              emails = {},
            }
          }

          local body = assert.res_status(400, res)
          local resp_body_json = cjson.decode(body)

          assert.same(expected, resp_body_json.message)
        end)
      end)
    end)

    -- TODO DEVX: write developer plugin tests
    describe("/developer/:developer/plugins", function()
    end)

    describe("/developer/:developer/plugins/:id", function()
    end)
  end)

  describe("/developers/:developers/credentials/:plugin", function()
    local developer

    after_each(function()
      assert(db:truncate())
    end)

    before_each(function()
      helpers.stop_kong()
      assert(db:truncate())

      assert(helpers.start_kong({
        database   = strategy,
        portal     = true,
        portal_auth = "basic-auth",
        portal_auth_config = "{ \"hide_credentials\": true }",
        portal_auto_approve = "off",
        portal_invite_email = "off",
      }))

      developer = assert(db.developers:insert {
        email = "gruce@konghq.com",
        password = "kong",
        meta = "{\"full_name\":\"I Like Turtles\"}",
        status = enums.CONSUMERS.STATUS.APPROVED,
      })

      for i = 1, 10 do
        assert(client_request({
          method = "POST",
          path = "/default/developers/" .. developer.id .. "/credentials/basic-auth",
          body = {
            username = 'dog' .. tostring(i),
            password = 'cat',
          },
          headers = {["Content-Type"] = "application/json"},
        }))
      end

      for i = 1, 5 do
        assert(client_request({
          method = "POST",
          path = "/default/developers/" .. developer.id .. "/credentials/key-auth",
          body = {
            key = 'bat' .. tostring(i),
          },
          headers = {["Content-Type"] = "application/json"},
        }))
      end

      client = assert(helpers.admin_client())
      configure_portal(dao)
    end)

    describe("POST", function()
      it("can create credentials", function()
        local res = assert(client_request({
          method = "POST",
          path = "/default/developers/" .. developer.id .. "/credentials/basic-auth",
          body = {
            username = 'dog20',
            password = 'cat',
          },
          headers = {["Content-Type"] = "application/json"},
        }))
        assert.res_status(200, res)

        res = assert(client:send {
          method = "GET",
          path = "/default/developers/" .. developer.id .. "/credentials/basic-auth"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(11, #json.data)
        for i, v in ipairs(json.data) do
          assert.truthy(string.match(json.data[i].username, 'dog'))
        end

        assert(client_request({
          method = "POST",
          path = "/default/developers/" .. developer.id .. "/credentials/key-auth",
          body = {
            key = 'bat420',
          },
          headers = {["Content-Type"] = "application/json"},
        }))
        res = assert(client:send {
          method = "GET",
          path = "/default/developers/" .. developer.id .. "/credentials/key-auth"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(6, #json.data)
        for i, v in ipairs(json.data) do
          assert.truthy(string.match(json.data[i].key, 'bat'))
        end
      end)
    end)

    describe("GET", function()
      it("retrieves credentials by type", function()
        local res = assert(client:send {
          method = "GET",
          path = "/default/developers/" .. developer.id .. "/credentials/basic-auth"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(10, #json.data)
        for i, v in ipairs(json.data) do
          assert.truthy(string.match(json.data[i].username, 'dog'))
        end

        local res = assert(client:send {
          method = "GET",
          path = "/default/developers/" .. developer.id .. "/credentials/key-auth"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(5, #json.data)
        for i, v in ipairs(json.data) do
          assert.truthy(string.match(json.data[i].key, 'bat'))
        end
      end)
    end)
  end)

  describe("/developers/:developers/credentials/:plugin/:credential_id", function()
    local res, developer, basic_auth, key_auth

    after_each(function()
      assert(db:truncate())
    end)

    before_each(function()
      helpers.stop_kong()
      assert(db:truncate())

      assert(helpers.start_kong({
        database   = strategy,
        portal     = true,
        portal_auth = "basic-auth",
        portal_auth_config = "{ \"hide_credentials\": true }",
        portal_auto_approve = "off",
        portal_invite_email = "off",
      }))

      developer = assert(db.developers:insert {
        email = "gruce@konghq.com",
        password = "kong",
        meta = "{\"full_name\":\"I Like Turtles\"}",
        status = enums.CONSUMERS.STATUS.APPROVED,
      })

      res = client_request({
        method = "POST",
        path = "/default/developers/" .. developer.id .. "/credentials/basic-auth",
        body = {
          username = 'dog',
          password = 'cat',
        },
        headers = {["Content-Type"] = "application/json"},
      })

      basic_auth = cjson.decode(res.body)

      res = client_request({
        method = "POST",
        path = "/default/developers/" .. developer.id .. "/credentials/key-auth",
        body = {
          key = 'bat',
        },
        headers = {["Content-Type"] = "application/json"},
      })

      key_auth = cjson.decode(res.body)

      client = assert(helpers.admin_client())
      configure_portal(dao)
    end)

    describe("GET", function()
      it("retrieves credentials by type", function()
        local res = assert(client:send {
          method = "GET",
          path = "/default/developers/" .. developer.id .. "/credentials/basic-auth/" .. basic_auth.id
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(json.id, basic_auth.id)
        assert.equal(json.username, basic_auth.username)

        local res = assert(client:send {
          method = "GET",
          path = "/default/developers/" .. developer.id .. "/credentials/key-auth/" .. key_auth.id
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(json.id, key_auth.id)
        assert.equal(json.key, key_auth.key)
      end)

      it("cannot retrieve credentials of wrong type", function()
        local res = assert(client:send {
          method = "GET",
          path = "/default/developers/" .. developer.id .. "/credentials/basic-auth/" .. key_auth.id
        })
        assert.res_status(404, res)

        local res = assert(client:send {
          method = "GET",
          path = "/default/developers/" .. developer.id .. "/credentials/key-auth/" .. basic_auth.id
        })
        assert.res_status(404, res)
      end)
    end)

    describe("PATCH", function()
      it("can update credential with valid params", function()
        local res = assert(client:send {
          method = "PATCH",
          body = {
            username = "woah-dude",
          },
          path = "/default/developers/" .. developer.id .. "/credentials/basic-auth/" .. basic_auth.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(json.id, basic_auth.id)
        assert.equal(json.username, "woah-dude")

        local res = assert(client:send {
          method = "PATCH",
          body = {
            key = "radical",
          },
          path = "/default/developers/" .. developer.id .. "/credentials/key-auth/" .. key_auth.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(json.id, key_auth.id)
        assert.equal(json.key, "radical")
      end)

      it("cannot update credential with invalid params", function()
        local res = assert(client:send {
          method = "PATCH",
          body = {
            usrname = "woah-dude",
          },
          path = "/default/developers/" .. developer.id .. "/credentials/basic-auth/" .. basic_auth.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(400, res)

        local res = assert(client:send {
          method = "PATCH",
          body = {
            keys = "radical",
          },
          path = "/default/developers/" .. developer.id .. "/credentials/key-auth/" .. key_auth.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(400, res)
      end)
    end)

    describe("DELETE", function()
      it("can delete credential", function()
        res = client_request({
          method = "POST",
          path = "/default/developers/" .. developer.id .. "/credentials/basic-auth",
          body = {
            username = 'test',
            password = 'test',
          },
          headers = {["Content-Type"] = "application/json"},
        })
        basic_auth = cjson.decode(res.body)

        res = client_request({
          method = "POST",
          path = "/default/developers/" .. developer.id .. "/credentials/key-auth",
          body = {
            key = 'test',
          },
          headers = {["Content-Type"] = "application/json"},
        })
        key_auth = cjson.decode(res.body)

        res = assert(client:send {
          method = "DELETE",
          path = "/default/developers/" .. developer.id .. "/credentials/basic-auth/" .. basic_auth.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(204, res)

        res = assert(client:send {
          method = "DELETE",
          path = "/default/developers/" .. developer.id .. "/credentials/key-auth/" .. key_auth.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(204, res)
      end)

      it("delete will always return 204 if they don't exist", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/default/developers/" .. developer.id .. "/credentials/basic-auth/" .. basic_auth.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(204, res)

        res = assert(client:send {
          method = "DELETE",
          path = "/default/developers/" .. developer.id .. "/credentials/key-auth/" .. key_auth.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(204, res)
      end)
    end)
  end)
end)
end
