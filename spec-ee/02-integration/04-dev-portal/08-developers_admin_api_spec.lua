-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson   = require "cjson"
local helpers = require "spec.helpers"
local enums       = require "kong.enterprise_edition.dao.enums"
local ee_helpers  = require "spec-ee.helpers"
local constants   = require "kong.constants"
local fmt = string.format
local clear_license_env = require("spec-ee.helpers").clear_license_env
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key


local PORTAL_SESSION_CONF = "{ \"secret\": \"super-secret\", \"cookie_secure\": false }"

local PORTAL_PREFIX = constants.PORTAL_PREFIX


local function configure_portal(config)
  if not config then
    config = {
      portal = true,
      portal_auth = "basic-auth",
    }
  end

  assert.res_status(204, (helpers.admin_client():delete("/cache")))

  assert(kong.db.workspaces:upsert_by_name("default", {
    name = "default",
    config = config
  }))
end


local function client_request(params)
  local client = assert(helpers.admin_client())
  local res = assert(client:send(params))
  res.body = res:read_body()
  client:close()

  return res
end


local function verify_order(data, key, sort_desc)
  for i = 1, #data - 1 do
    local current_val = data[i][key]
    local next_val = data[i + 1][key]

    local current_is_nil = current_val == nil
    local next_is_nil = next_val == nil

    if current_is_nil then
      assert.is_true(not sort_desc or next_is_nil)
    elseif next_is_nil then
      assert.is_true(sort_desc)
    else
      assert.is_true(current_val == next_val or current_val > next_val == sort_desc)
    end
  end
end


for _, strategy in helpers.each_strategy() do

describe("Admin API - Developer Portal - #" .. strategy, function()
  local client, portal_api_client
  local bp, db
  local reset_license_data

  bp, db, _ = helpers.get_db_utils(strategy)

  lazy_setup(function()
    reset_license_data = clear_license_env()
    kong.configuration = {
      portal_auth = "basic-auth",
    }

    assert(helpers.start_kong({
      license_path = "spec-ee/fixtures/mock_license.json",
      portal = true,
      portal_and_vitals_key = get_portal_and_vitals_key(),
      portal_auth = "basic-auth",
      portal_session_conf = PORTAL_SESSION_CONF,
      database = strategy,
    }))

    local store = {}
    kong.cache = {
      get = function(_, key, _, f, ...)
        store[key] = store[key] or f(...)
        return store[key]
      end,
      invalidate = function(_, key)
        store[key] = nil
        return true
      end,
    }
  end)

  lazy_teardown(function()
    helpers.stop_kong()
    reset_license_data()
  end)

  before_each(function()
    client = helpers.admin_client()
    portal_api_client = ee_helpers.portal_api_client()
    configure_portal()
  end)

  after_each(function()
    if client then client:close() end
    if portal_api_client then portal_api_client:close() end
  end)

  describe("/developers", function()
    describe("GET", function ()
      lazy_setup(function()
        configure_portal()
      end)

      lazy_teardown(function()
        assert(db:truncate())
      end)

      before_each(function()
        assert(client_request({
          method = "POST",
          path = "/developers/roles",
          body = {
            name = "red"
          },
          headers = {["Content-Type"] = "application/json"},
        }))

        assert(client_request({
          method = "POST",
          path = "/developers/roles",
          body = {
            name = "blue"
          },
          headers = {["Content-Type"] = "application/json"},
        }))

        for i = 1, 5 do
          assert(db.developers:insert {
            email = "developer-" .. i .. "@dog.com",
            meta = '{"full_name":"Testy Mctesty Face"}',
            password = "pw",
          })
        end

        for i = 1, 5 do
          assert(db.developers:insert {
            email = "developer-" .. i .. "@cat.com",
            meta = '{"full_name":"Testy Mctesty Face 2"}',
            password = "pw",
            roles = {"red"},
          })
        end

        for i = 1, 5 do
          assert(db.developers:insert {
            email = "developer-" .. i .. "@cow.com",
            meta = '{"full_name":"Testy Mctesty Face 3"}',
            password = "pw",
            roles = {"blue"},
          })
        end
      end)

      after_each(function()
        assert(db:truncate("rbac_roles"))
        assert(db:truncate("developers"))
        assert(db:truncate("consumers"))
        assert(db:truncate("basicauth_credentials"))
      end)

      it("retrieves list of developers only", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/developers"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(15, #json.data)
      end)

      it("filters by developer status", function()
        assert(db.developers:insert {
          email = "developer-pending@dog.com",
          status = enums.CONSUMERS.STATUS.APPROVED,
          password = "pw",
          meta = '{"full_name":"Pending Name"}',
        })

        local res = assert(client:send {
          method = "GET",
          path = "/developers?size=5&status=" .. enums.CONSUMERS.STATUS.APPROVED
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(1, #json.data)
        assert.equal(ngx.null, json.next)
      end)

      it("filters by role", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/developers?size=2&role=red"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(2, #json.data)

        for i, developer in ipairs(json.data) do
          assert.equal("red", developer.roles[1])
        end

        local next = json.next

        local res = assert(client:send {
          methd = "GET",
          path = next
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(2, #json.data)

        for i, developer in ipairs(json.data) do
          assert.equal("red", developer.roles[1])
        end

        local next = json.next

        local res = assert(client:send {
          methd = "GET",
          path = next
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(1, #json.data)

        local developer = json.data[1]
        assert.equal("red", developer.roles[1])
        assert.equal(ngx.null, json.next)
      end)

      it("paginates correctly", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/developers?size=5"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(5, #json.data)

        local next = json.next

        local res = assert(client:send {
          methd = "GET",
          path = next
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(5, #json.data)

        local next = json.next

        local res = assert(client:send {
          methd = "GET",
          path = next
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(5, #json.data)
        assert.equal(ngx.null, json.next)
      end)

      it("return 400 if size is less than 1", function ()
        local res = assert(client:send {
          method = "GET",
          path = "/developers?size=0",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(400, res)
        local resp_body_json = cjson.decode(body)

        assert.equal("invalid size", resp_body_json.message)
      end)

      it("return 400 if size is greater than 1000", function ()
        local res = assert(client:send {
          method = "GET",
          path = "/developers?size=1001",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(400, res)
        local resp_body_json = cjson.decode(body)

        assert.equal("invalid size", resp_body_json.message)
      end)

      it("sorts by id ASC by default", function()
        local res = assert(client:send({
          method = "GET",
          path = "/developers",
          headers = {["Content-Type"] = "application/json"}
        }))

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        assert.equal(15, resp_body_json.total)

        verify_order(resp_body_json.data, "id", false)
      end)

      it("sorts by id DESC with 'sort_desc=true' param", function()
        local res = assert(client:send({
          method = "GET",
          path = "/developers?sort_desc=true",
          headers = {["Content-Type"] = "application/json"}
        }))

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        assert.equal(15, resp_body_json.total)

        verify_order(resp_body_json.data, "id", true)
      end)

      it("sorts by email ASC with 'sort_by=email' param", function()
        local res = assert(client:send({
          method = "GET",
          path = "/developers?sort_by=email",
          headers = {["Content-Type"] = "application/json"}
        }))

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        assert.equal(15, resp_body_json.total)

        verify_order(resp_body_json.data, "email", false)
      end)

      it("sorts by email DESC with 'sort_by=email&sort_desc=true' param", function()
        local res = assert(client:send({
          method = "GET",
          path = "/developers?sort_by=email&sort_desc=true",
          headers = {["Content-Type"] = "application/json"}
        }))

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        assert.equal(15, resp_body_json.total)

        verify_order(resp_body_json.data, "email", true)
      end)

      it("maintains sort across pages ASC", function()
        local res = assert(client:send({
          method = "GET",
          path = "/developers?sort_by=email&size=4",
          headers = {["Content-Type"] = "application/json"}
        }))

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        assert.equal(4, resp_body_json.total)

        verify_order(resp_body_json.data, "email", false)

        local last_name_first_page = resp_body_json.data[#resp_body_json.data]

        local res = assert(client:send {
          method = "GET",
          path = resp_body_json.next,
          headers = {["Content-Type"] = "application/json"}
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        assert.equal(4, resp_body_json.total)

        verify_order(resp_body_json.data, "email", false)

        local first_name_second_page = resp_body_json.data[1]

        verify_order({last_name_first_page, first_name_second_page}, "email", false)
      end)

      it("maintains sort across pages DESC", function()
        local res = assert(client:send({
          method = "GET",
          path = "/developers?sort_by=email&size=4&sort_desc=true",
          headers = {["Content-Type"] = "application/json"}
        }))

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        assert.equal(4, resp_body_json.total)

        verify_order(resp_body_json.data, "email", true)

        local last_name_first_page = resp_body_json.data[#resp_body_json.data]

        local res = assert(client:send {
          method = "GET",
          path = resp_body_json.next,
          headers = {["Content-Type"] = "application/json"}
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        assert.equal(4, resp_body_json.total)

        verify_order(resp_body_json.data, "email", true)

        local first_name_second_page = resp_body_json.data[1]

        verify_order({last_name_first_page, first_name_second_page}, "email", true)
      end)

      it("return null 'next' when role is not found after the first page", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/developers?size=5&role=red"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(5, #json.data)

        for i, developer in ipairs(json.data) do
          assert.equal("red", developer.roles[1])
        end

        assert.equal(ngx.null, json.next)
      end)
    end)

    describe("POST", function ()
      lazy_setup(function()
        local store = {}
        kong.cache = {
          get = function(_, key, _, f, ...)
            store[key] = store[key] or f(...)
            return store[key]
          end,
          invalidate = function(key)
            store[key] = nil
          end,
        }
        bp.rbac_roles:insert({ name = PORTAL_PREFIX .. "red" })
        configure_portal()
      end)

      lazy_teardown(function()
        assert(db:truncate())
      end)

      it("creates a developer with roles associated", function()
        local res = client:post("/developers", {
          body = {
            email = "a@a.com",
            meta = '{"full_name":"a"}',
            password = "test",
            roles = { "red" },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal("a@a.com", json.email)
        assert.same({ "red" }, json.roles)
        end)
      
        it("should return 400 if creates a developer with invalid roles", function()
          local res = client:post("/developers", {
            body = {
              email = "a1@a.com",
              meta = '{"full_name":"a1"}',
              password = "test1",
              roles = "red" ,
            },
            headers = { ["Content-Type"] = "application/json" },
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.equal("the roles of developer should be an array.", json.fields.roles)
        end)

      it("creates a developer with custom_id", function()
        local res = client:post("/developers", {
          body = {
            email = "b@b.com",
            meta = '{"full_name":"a"}',
            password = "test",
            custom_id = "friendo",
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equals("b@b.com", json.email)
        assert.equals("friendo", json.custom_id)

        -- checking that consumer custom_id is set as well
        local consumer = kong.db.consumers:select({
          id = json.consumer.id
        })

        assert.equals("friendo", consumer.custom_id)
      end)
    end)
  end)

  describe("/developers/download", function()
    lazy_setup(function()
      configure_portal()
    end)

    lazy_teardown(function()
      assert(db:truncate())
    end)

    before_each(function()
      assert(client_request({
        method = "POST",
        path = "/developers/roles",
        body = {
          name = "red"
        },
        headers = {["Content-Type"] = "application/json"},
      }))

      assert(client_request({
        method = "POST",
        path = "/developers/roles",
        body = {
          name = "blue"
        },
        headers = {["Content-Type"] = "application/json"},
      }))

      for i = 1, 5 do
        assert(db.developers:insert {
          email = "developer-" .. i .. "@dog.com",
          meta = '{"full_name":"Testy Mctesty Face"}',
          password = "pw",
        })
      end

      for i = 1, 5 do
        assert(db.developers:insert {
          email = "developer-" .. i .. "@cat.com",
          meta = '{"full_name":"Testy Mctesty Face 2"}',
          password = "pw",
          roles = {"red"},
        })
      end

      for i = 1, 5 do
        assert(db.developers:insert {
          email = "developer-" .. i .. "@cow.com",
          meta = '{"full_name":"Testy Mctesty Face 3"}',
          password = "pw",
          roles = {"blue"},
        })
      end
    end)

    after_each(function()
      assert(db:truncate("rbac_roles"))
      assert(db:truncate("developers"))
      assert(db:truncate("consumers"))
      assert(db:truncate("basicauth_credentials"))
    end)


    it("exports the list of developers as a csv string", function()
      local res = assert(client:send {
        methd = "GET",
        path = "/developers/export"
      })
      local body = assert.res_status(200, res)

      assert.equals('text/csv', res.headers["Content-Type"])
      assert.equals(true, body:find('^Email, Status') ~= nil)
      assert.equals(5, select(2, string.gsub(body, "cat.com", "")))
      assert.equals(5, select(2, string.gsub(body, "dog.com", "")))
      assert.equals(5, select(2, string.gsub(body, "cow.com", "")))
    end)

  end)

  describe("/developers/:developers", function()
    local developer

    lazy_setup(function()
      local store = {}
      kong.cache = {
        get = function(_, key, _, f, ...)
          store[key] = store[key] or f(...)
          return store[key]
        end,
        invalidate = function(key)
          store[key] = nil
        end,
      }

      bp.rbac_roles:insert({ name = PORTAL_PREFIX .. "red" })
      bp.rbac_roles:insert({ name = PORTAL_PREFIX .. "green" })
      developer = assert(db.developers:insert({
        email = "gruce@konghq.com",
        password = "kong",
        meta = "{\"full_name\":\"I Like Turtles\"}",
        status = enums.CONSUMERS.STATUS.REJECTED,
        roles = { "red" },
        custom_id = "special"
      }))
      configure_portal()
    end)

    lazy_teardown(function()
      assert(db:truncate())
    end)

    describe("GET", function()
      it("fetches the developer and associated roles", function()
        local res = client:get("/developers/gruce@konghq.com")

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(developer.email, json.email)
        assert.equals(developer.password, json.password)
        assert.equals(developer.meta, json.meta)
        assert.equals(developer.status, json.status)
        assert.is_table(developer.rbac_user)
        assert.same({ "red" }, json.roles)
        assert.equals(developer.custom_id, json.custom_id)
      end)
    end)

    describe("PATCH", function()
      after_each(function()
        assert(db.developers:update(
          { id = developer.id },
          { email = "gruce@konghq.com", }
        ))
      end)

      it("updates the developer email, username, login credential, roles, and custom_id", function()
        local res = assert(client:send {
          method = "PATCH",
          body = {
            email = "new_email@whodis.com",
            status = enums.CONSUMERS.STATUS.APPROVED,
            roles = { "green" },
            custom_id = "radical",
          },
          path = "/developers/".. developer.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        local consumer = kong.db.consumers:select({
          id = resp_body_json.developer.consumer.id
        })

        assert.equals("new_email@whodis.com", resp_body_json.developer.email)
        assert.equals("new_email@whodis.com", consumer.username)
        assert.same({ "green" }, resp_body_json.developer.roles)
        assert.equals("radical", resp_body_json.developer.custom_id)
        assert.equals("radical", consumer.custom_id)

        -- old email fails to access portal api
        local res = assert(portal_api_client:send {
          method = "GET",
          path = "/auth",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.equals("Unauthorized", json.message)

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
      
      it("return 400 if updates the roles of the developer type is a string", function ()
          local res = assert(client:send {
            method = "PATCH",
            body = {
              roles = "green",
            },
            path = "/developers/" .. developer.id,
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.equal("the roles of developer should be an array.", json.fields.roles)
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

      it("returns 409 if patched with a custom_id that already exists", function()

        local developer2 = assert(db.developers:insert {
          email = "someonenew@konghq.com",
          password = "woof",
          meta = "{\"full_name\":\"Scoopy Doo\"}",
          custom_id = "ruh roh",
        })

        local res = assert(client:send {
          method = "PATCH",
          body = {
            custom_id = developer2.custom_id,
          },
          path = "/developers/".. developer.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(409, res)
        local resp_body_json = cjson.decode(body)
        local fields = resp_body_json.fields

        assert.equal("already exists with value 'ruh roh'", fields.custom_id)
      end)

      it("returns 400 if patch a verified developer to type 'UNVERIFIED'", function()
        local developer3 = assert(db.developers:insert {
          email = "fancypants2@konghq.com",
          password = "mowmow",
          status = 0,
          meta = "{\"full_name\":\"Old Gregg\"}"
        })

        local res = assert(client:send {
          method = "PATCH",
          body = {
            status = 5,
          },
          path = "/developers/".. developer3.email,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(400, res)
        local resp_body_json = cjson.decode(body)
        local fields = resp_body_json.fields

        assert.equal("cannot update developer to status UNVERIFIED", fields.status)
      end)

      it("updates the developer meta with valid meta", function()
        local meta = '{"full_name":"Testy Facey McTesty Test"}'
        local res = assert(client:send {
          method = "PATCH",
          body = {
            meta = meta,
          },
          path = "/developers/".. developer.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        assert.equals(meta, resp_body_json.developer.meta)
      end)

      it("updates email meta with validation against developer_meta_fields", function()
        local meta_fields = cjson.encode({{
            label = "personal email",
            title = "p_email",
            is_email = true,
            validator = {
              type = "string",
              required = true,
            },
          }
        })
        assert(db.workspaces:upsert_by_name("default", {
          name = "default",
          config = {
            portal = true,
            portal_auth = "basic-auth",
            portal_developer_meta_fields = meta_fields
          }
        }))

        local bad_email_meta = '{"p_email":"McTesty Test"}'
        local res = assert(client:send {
          method = "PATCH",
          body = {
            meta = bad_email_meta,
          },
          path = "/developers/".. developer.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(400, res)
        local resp_body_json = cjson.decode(body)

        assert.equals("McTesty Test is not a valid email missing '@' symbol", resp_body_json.fields.meta)

        local good_email_meta = '{"p_email":"mctesty.test@whodis.com"}'
        local res = assert(client:send {
          method = "PATCH",
          body = {
            meta = good_email_meta,
          },
          path = "/developers/".. developer.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        assert.equals(good_email_meta, resp_body_json.developer.meta)
      end)

      it("updates number meta with validation against developer_meta_fields", function()
        local meta_fields = cjson.encode({{
            label = "Magic Number",
            title = "magic_number",
            validator = {
              type = "number",
              required = true,
            },
          }
        })
        assert(db.workspaces:upsert_by_name("default", {
          name = "default",
          config = {
            portal = true,
            portal_auth = "basic-auth",
            portal_developer_meta_fields = meta_fields
          }
        }))
        local bad_meta = '{"magic_number":"not a number"}'
        local res = assert(client:send {
          method = "PATCH",
          body = {
            meta = bad_meta,
          },
          path = "/developers/".. developer.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(400, res)
        local resp_body_json = cjson.decode(body)

        assert.equals('expected a number', resp_body_json.fields.meta.magic_number)

        -- We expect the front end to input stringy numbers
        local good_meta = '{"magic_number":"42"}'
        local res = assert(client:send {
          method = "PATCH",
          body = {
            meta = good_meta,
          },
          path = "/developers/".. developer.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        assert.equals(good_meta, resp_body_json.developer.meta)
      end)

      it("updates developer meta but only fully, no partial meta update", function()
        local meta_fields = cjson.encode({{
            label = "Full Name",
            title = "full_name",
            validator = {
              type = "string",
              required = true,
            }
          }, {
            label = "Personal Email",
            title = "personal_email",
            is_email = true,
            validator = {
              type = "string",
              required = true,
            }
          },
        })
        assert(db.workspaces:upsert_by_name("default", {
          name = "default",
          config = {
            portal = true,
            portal_auth = "basic-auth",
            portal_developer_meta_fields = meta_fields
          }
        }))
        --set orginal meta
        local orginal_meta = '{"full_name":"Gruce", "personal_email": "gruce@konghq.com"}'
        local res = assert(client:send {
          method = "PATCH",
          body = {
            meta = orginal_meta,
          },
          path = "/developers/".. developer.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        assert.equals(orginal_meta, resp_body_json.developer.meta)

        local bad_meta = '{"personal_email":"mr.gruce@konghq.com"}'
        local res = assert(client:send {
          method = "PATCH",
          body = {
            meta = bad_meta,
          },
          path = "/developers/".. developer.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(400, res)
        local resp_body_json = cjson.decode(body)

        assert.equals("required field missing", resp_body_json.fields.meta.full_name)

        local new_meta = '{"full_name":"Mr. Gruce", "personal_email": "gruce@konghq.com"}'
        local res = assert(client:send {
          method = "PATCH",
          body = {
            meta = new_meta,
          },
          path = "/developers/".. developer.id,
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)

        assert.equals(new_meta, resp_body_json.developer.meta)
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

    describe("DELETE", function()
      it("deletes a developer by primary_key", function()
        local other_developer = assert(db.developers:insert({
          email = "other_doggo@konghq.com",
          password = "blep",
          meta = "{\"full_name\":\"Woof\"}",
          status = enums.CONSUMERS.STATUS.APPROVED,
          custom_id = "mlerm"
        }))

        local res = client:get("/developers/" .. other_developer.id)
        assert.res_status(200, res)

        res = client:delete("/developers/" .. other_developer.id)
        assert.res_status(204, res)

        res = client:get("/developers/" .. other_developer.id)
        assert.res_status(404, res)
      end)
      
      it("deletes a developer by email", function()
        local email = "other_doggo@konghq.com"
        -- first insert 
        local res = client:post("/developers", {
          body = {
            email = email,
            meta = '{"full_name":"a"}',
            password = "test",
            status = enums.CONSUMERS.STATUS.APPROVED,
            custom_id = "friendo",
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        assert.res_status(200, res)

        local res = client:get("/developers/" .. email)
        assert.res_status(200, res)

        -- delete developer by email
        res = client:delete("/developers/" .. email)
        assert.res_status(204, res)

        -- check if delete success
        local res = client:get("/developers/" .. email)
        assert.res_status(404, res)
        
        -- second insert with email
        local res = client:post("/developers", {
          body = {
            email = email,
            meta = '{"full_name":"a"}',
            password = "test",
            status = enums.CONSUMERS.STATUS.APPROVED,
            custom_id = "friendo",
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        assert.res_status(200, res)
        
        -- check developer insert success
        res = client:get("/developers/" .. email)
        assert.res_status(200, res)
      end)

      it("deletes a developer who has a role assigned to it (regression)", function()
        local another_developer = assert(db.developers:insert({
          email = "another_doggo@konghq.com",
          password = "blep",
          meta = "{\"full_name\":\"Woof\"}",
          status = enums.CONSUMERS.STATUS.APPROVED,
          custom_id = "mlerm_mlerm"
        }))

        local res = client:get("/developers/" .. another_developer.id)
        assert.res_status(200, res)

        res = assert(client:post("/developers/roles", {
          body = {
            name = "doggo_role",
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))

        assert.res_status(201, res)

        res = assert(client:patch("/developers/" .. another_developer.id, {
          body = {
            roles = { "doggo_role" },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same({"doggo_role"}, json.developer.roles)

        res = client:delete("/developers/" .. another_developer.id)
        assert.res_status(204, res)

        res = client:get("/developers/" .. another_developer.id)
        assert.res_status(404, res)
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
            license_path = "spec-ee/fixtures/mock_license.json",
            portal     = true,
            portal_and_vitals_key = get_portal_and_vitals_key(),
            portal_auth = "basic-auth",
            portal_session_conf = PORTAL_SESSION_CONF,
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "off",
            portal_invite_email = "off",
          }))

          client = assert(helpers.admin_client())
          configure_portal()
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
        lazy_setup(function()
          helpers.stop_kong()
          assert(helpers.start_kong({
            database   = strategy,
            license_path = "spec-ee/fixtures/mock_license.json",
            portal     = true,
            portal_and_vitals_key = get_portal_and_vitals_key(),
            portal_auth = "basic-auth",
            portal_session_conf = PORTAL_SESSION_CONF,
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "off",
            portal_emails_from = "me@example.com",
            portal_emails_reply_to = "me@example.com",
            smtp = "on",
            smtp_mock = "on",
          }))

          client = assert(helpers.admin_client())
          configure_portal()
        end)

        before_each(function()
          db:truncate("developers")
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
    pending("/developer/:developer/plugins", function() end)
    pending("/developer/:developer/plugins/:id", function() end)
  end)

  describe("/developers/:developers/credentials/:plugin", function()
    local developer

    after_each(function()
      assert(db:truncate("rbac_roles"))
      assert(db:truncate("developers"))
      assert(db:truncate("consumers"))
      assert(db:truncate("basicauth_credentials"))
      assert(db:truncate("keyauth_credentials"))
    end)

    lazy_setup(function()
      helpers.stop_kong()
      assert(db:truncate())
      assert(helpers.start_kong({
        database   = strategy,
        license_path = "spec-ee/fixtures/mock_license.json",
        portal     = true,
        portal_and_vitals_key = get_portal_and_vitals_key(),
        portal_auth = "basic-auth",
        portal_session_conf = PORTAL_SESSION_CONF,
        portal_auth_config = "{ \"hide_credentials\": true }",
        portal_auto_approve = "off",
        portal_invite_email = "off",
      }))

      client = assert(helpers.admin_client())
    end)

    before_each(function()
      developer = assert(db.developers:insert {
        email = "gruce@konghq.com",
        password = "kong",
        meta = "{\"full_name\":\"I Like Turtles\"}",
        status = enums.CONSUMERS.STATUS.APPROVED,
      })

      configure_portal()

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
        assert.res_status(201, res)

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
      assert(db:truncate("rbac_roles"))
      assert(db:truncate("developers"))
      assert(db:truncate("consumers"))
      assert(db:truncate("basicauth_credentials"))
      assert(db:truncate("keyauth_credentials"))
    end)

    lazy_setup(function()
      helpers.stop_kong()
      assert(helpers.start_kong({
        database   = strategy,
        license_path = "spec-ee/fixtures/mock_license.json",
        portal     = true,
        portal_and_vitals_key = get_portal_and_vitals_key(),
        portal_auth = "basic-auth",
        portal_session_conf = PORTAL_SESSION_CONF,
        portal_auth_config = "{ \"hide_credentials\": true }",
        portal_auto_approve = "off",
        portal_invite_email = "off",
      }))
      configure_portal()
      client = assert(helpers.admin_client())
    end)

    before_each(function()
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

  describe("/developers/roles", function()
    before_each(function()
      assert(db:truncate("rbac_roles"))
      configure_portal()
    end)

    describe("GET", function()
      it("retrieves list of roles which are prefixed", function()
        bp.rbac_roles:insert({ name = PORTAL_PREFIX .. "red" })
        bp.rbac_roles:insert({ name = PORTAL_PREFIX .. "blue" })
        bp.rbac_roles:insert({ name = PORTAL_PREFIX .. "green" })
        bp.rbac_roles:insert({ name = "should_not_appear" })

        local res = client:get("/developers/roles")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(3, #json.data)
        local names = {}
        for i = 1, 3 do
          names[i] = json.data[i].name
        end
        table.sort(names)
        assert.same({ "blue", "green", "red" }, names)
      end)
    end)

    describe("POST", function()
      it("creates a new rbac role, prefixing it. The returned one is not prefixed, has no is_default, and has a permissions attribute", function()
        local res = client:post("/developers/roles", {
          body = { name = "red" },
          headers = { ["content-type"] = "application/json" },
        })
        local body = assert.res_status(201, res)
        local dev_role = cjson.decode(body)
        assert.equals("red", dev_role.name)
        assert.is_nil(dev_role.is_default)
        assert.same({}, dev_role.permissions)

        local res = client:get("/rbac/roles/" .. PORTAL_PREFIX .. "red")
        local body = assert.res_status(200, res)
        local rbac_role = cjson.decode(body)
        assert.equals(PORTAL_PREFIX .. "red", rbac_role.name)
        assert.is_false(rbac_role.is_default)
        assert.is_nil(rbac_role.permissions)

        assert.equals(dev_role.id, rbac_role.id)
      end)

      it("returns 400 if attempting to create role named '*'", function()
        local res = client:post("/developers/roles", {
          body = { name = "*" },
          headers = { ["content-type"] = "application/json" },
        })
        local body = assert.res_status(400, res)
        local resp_body_json = cjson.decode(body)

        assert.equal("Invalid role '*'", resp_body_json.message)
      end)
    end)
  end)

  describe("/developers/roles/:role", function()
    before_each(function()
      assert(db:truncate("rbac_roles"))
      assert(db:truncate("rbac_role_endpoints"))
      configure_portal()
    end)

    describe("GET", function()
      it("returns an existing rbac role, non-prefixed and without is_default, and with a permissions property", function()
        local role = bp.rbac_roles:insert({ name = PORTAL_PREFIX .. "red" })

        local res = client:get("/developers/roles/red")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals("red", json.name)
        assert.same({}, json.permissions)
        assert.is_nil(json.is_default)

        local res = client:post(fmt("/rbac/roles/%s/endpoints", role.id), {
          body = {
            endpoint = "/foo",
            workspace = "default",
            actions = "read",
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        assert.res_status(201, res)

        local res = client:get("/developers/roles/red")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same({
          default = {
            ["/default/foo"] = {
              actions = {
                read = {
                  negative = false
                },
              },
            }
          }
        }, json.permissions)
      end)
      it("returns 404 on non-existing or unprefixed roles", function()
        bp.rbac_roles:insert({ name = "rbac_role" })

        local res = client:get("/developers/roles/foo")
        assert.res_status(404, res)

        local res = client:get("/developers/roles/rbac_role")
        assert.res_status(404, res)
      end)
    end)

    describe("PATCH", function()
      it("updates an existing rbac role, non-prefixed and without is_default, and with permissions attribute", function()
        local role = bp.rbac_roles:insert({ name = PORTAL_PREFIX .. "red" })
        assert(db.rbac_role_endpoints:insert({
          role = { id = role.id },
          workspace = "default",
          endpoint = "/foo",
          actions = 0x1,
        }))

        local res = client:patch("/developers/roles/red", {
          body = { comment = "hello", name = "blue" },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals("hello", json.comment)
        assert.equals("blue", json.name)
        assert.is_nil(json.is_default)
        assert.same({
          default = {
            ["/default/foo"] = {
              actions = {
                read = {
                  negative = false
                },
              },
            }
          }
        }, json.permissions)

        local res = client:get("/developers/roles/blue")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals("hello", json.comment)
        assert.equals("blue", json.name)
        assert.is_nil(json.is_default)
        assert.same({
          default = {
            ["/default/foo"] = {
              actions = { read = { negative = false } },
            }
          }
        }, json.permissions)

      end)
      it("returns 404 on non-existing or unprefixed roles", function()
        bp.rbac_roles:insert({ name = PORTAL_PREFIX .. "red" })

        local res = client:patch("/developers/roles/foo")
        assert.res_status(404, res)

        local res = client:patch("/developers/roles/rbac_role")
        assert.res_status(404, res)
      end)

      it("returns 400 if attempting to patch an existing role with new name '*'", function()
        bp.rbac_roles:insert({ name = PORTAL_PREFIX .. "red" })
        local res = client:patch("/developers/roles/red", {
          body = { name = "*" },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(400, res)
        local resp_body_json = cjson.decode(body)

        assert.equal("Invalid role '*'", resp_body_json.message)
      end)
    end)

    describe("DELETE", function()

      it("deletes an existing rbac role", function()
        bp.rbac_roles:insert({ name = PORTAL_PREFIX .. "red" })
        local res = client:delete("/developers/roles/red")
        assert.res_status(204, res)

        local res = client:get("/developers/roles/red")
        assert.res_status(404, res)
      end)
    end)
  end)
end)
end
