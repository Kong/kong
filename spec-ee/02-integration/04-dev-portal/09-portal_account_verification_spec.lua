local cjson   = require "cjson"
local helpers = require "spec.helpers"
local uuid    = require("kong.tools.utils").uuid
local ee_jwt  = require "kong.enterprise_edition.jwt"
local ee_helpers = require "spec-ee.helpers"
local enums = require "kong.enterprise_edition.dao.enums"

local time = ngx.time

local PORTAL_SESSION_CONF = "{ \"secret\": \"super-secret\", \"cookie_secure\": false }"

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


local function api_client_request(params)
  local portal_api_client = assert(ee_helpers.portal_api_client())
  local res = assert(portal_api_client:send(params))
  res.body = res.body_reader()

  close_clients({ portal_api_client })
  return res
end


local function register_developer(params, workspace)
  workspace = workspace or "default"
  return api_client_request({
    method = "POST",
    path = "/" .. workspace .. "/register",
    body = params,
    headers = {["Content-Type"] = "application/json"},
  })
end


local function configure_portal(db, params)
  if not params then
    params = {
      portal = true,
    }
  end

  return db.workspaces:upsert_by_name("default", {
    name = "default",
    config = params,
  })
end


local function get_pending_tokens(db, developer)
  local pending = {}
  for secret in db.consumer_reset_secrets:each_for_consumer({ id = developer.consumer.id}) do
    if secret.status == enums.TOKENS.STATUS.PENDING then
      pending[#pending + 1] = secret
    end
  end

  return pending
end


for _, strategy in helpers.each_strategy() do
  describe("Account Verification [#" .. strategy .. "]", function()
    local db
    local secret

    lazy_setup(function()
      _, db, _ = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database    = strategy,
        portal      = true,
        enforce_rbac = "off",
        validate_portal_emails = true,
        portal_email_verification = true,
        portal_session_conf = PORTAL_SESSION_CONF,
      }))
    end)

    after_each(function()
      db:truncate()
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    describe("/verify-account", function()
      local unverified_developer

      before_each(function()
        configure_portal(db, {
          portal = true,
          portal_auth = "basic-auth",
          portal_auto_approve = true,
        })

        local res = register_developer({
          email = "kongkong@konghq.com",
          password = "wowza",
          meta = "{\"full_name\":\"1337\"}",
        })

        assert.equals(200, res.status)
        local resp_body_json = cjson.decode(res.body)
        unverified_developer = resp_body_json.developer

        secret = get_pending_tokens(db, unverified_developer)[1].secret
      end)

      after_each(function()
        db:truncate()
      end)

      it("should return 400 if called without a token", function()
        local res = api_client_request({
          method = "POST",
          path = "/verify-account",
          body = {
            token = "",
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(400, res.status)
        local resp_body_json = cjson.decode(res.body)
        local message = resp_body_json.message

        assert.equal("token is required", message)
      end)

      it("should return 401 if called with an invalid jwt format", function()
        local res = api_client_request({
          method = "POST",
          path = "/verify-account",
          body = {
            token = "im_a_token_lol",
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(401, res.status)
        local resp_body_json = cjson.decode(res.body)
        local message = resp_body_json.message

        assert.equal("Unauthorized", message)
      end)

      it("should return 401 if token is signed with an invalid secret", function()
        local claims = {id = unverified_developer.consumer.id, exp = time() + 100000}
        local bad_jwt = ee_jwt.generate_JWT(claims, "bad_secret")

        local res = api_client_request({
          method = "POST",
          path = "/verify-account",
          body = {
            token = bad_jwt,
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(401, res.status)
        local resp_body_json = cjson.decode(res.body)
        local message = resp_body_json.message

        assert.equal("Unauthorized", message)
      end)

      it("should return 401 if token is expired", function()
        local claims = {id = unverified_developer.consumer.id, exp = time() - 100000}
        local expired_jwt = ee_jwt.generate_JWT(claims, secret)

        local res = api_client_request({
          method = "POST",
          path = "/verify-account",
          body = {
            token = expired_jwt,
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(401, res.status)
        local resp_body_json = cjson.decode(res.body)
        local message = resp_body_json.message

        assert.equal("Unauthorized", message)
      end)

      it("should return 401 if token contains non-existent developer", function()
        local claims = {id = uuid(), exp = time() + 100000}
        local random_uuid_jwt = ee_jwt.generate_JWT(claims, secret)

        local res = api_client_request({
          method = "POST",
          path = "/verify-account",
          body = {
            token = random_uuid_jwt,
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(401, res.status)
      end)

      it("should return 200 if account successfully verifies with auto-approve on", function()
        local claims = {id = unverified_developer.consumer.id, exp = time() + 100000}
        local valid_jwt = ee_jwt.generate_JWT(claims, secret)

        local res = api_client_request({
          method = "POST",
          path = "/verify-account",
          body = {
            token = valid_jwt,
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(200, res.status)
        local resp_body_json = cjson.decode(res.body)
        assert.equals(0, resp_body_json.status)
        local developer = db.developers:select({ id = unverified_developer.id })
        assert.equals(0, developer.status)
      end)

      it("should return 200 if account successfully verifies with auto-approve on", function()
        configure_portal(db, {
          portal = true,
          portal_auth = "basic-auth",
          portal_auto_approve = false,
        })

        local claims = {id = unverified_developer.consumer.id, exp = time() + 100000}
        local valid_jwt = ee_jwt.generate_JWT(claims, secret)

        local res = api_client_request({
          method = "POST",
          path = "/verify-account",
          body = {
            token = valid_jwt,
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(200, res.status)

        local developer = db.developers:select({ id = unverified_developer.id })
        assert.equals(1, developer.status)
      end)
    end)

    describe("/resend-account-verification", function()
      local unverified_developer

      before_each(function()
        configure_portal(db, {
          portal = true,
          portal_auth = "basic-auth",
          portal_auto_approve = true,
        })

        local res = register_developer({
          email = "kongkong@konghq.com",
          password = "wowza",
          meta = "{\"full_name\":\"1337\"}",
        })

        assert.equals(200, res.status)
        local resp_body_json = cjson.decode(res.body)
        unverified_developer = resp_body_json.developer

        secret = get_pending_tokens(db, unverified_developer)[1].secret
      end)

      after_each(function()
        db:truncate()
      end)

      it("should return 400 if called without an email", function()
        local res = api_client_request({
          method = "POST",
          path = "/resend-account-verification",
          body = {},
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(400, res.status)
        local resp_body_json = cjson.decode(res.body)
        local message = resp_body_json.message

        assert.equal("Email is required", message)
      end)

      it("should return 204 if called with a non existent email", function()
        local res = api_client_request({
          method = "POST",
          path = "/resend-account-verification",
          body = {
            email = "dog@cat.com",
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(204, res.status)
      end)

      it("should return 200 and exit early if developer already verified", function()
        local res = client_request({
          method = "POST",
          path = "/developers",
          body = {
            email = "dog@cat.com",
            status = 0,
            password = "test",
            meta = '{"full_name": "dog"}'
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(200, res.status)

        local res = api_client_request({
          method = "POST",
          path = "/resend-account-verification",
          body = {
            email = "dog@cat.com",
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(204, res.status)

        local res = client_request({
          method = "GET",
          path = "/developers/dog@cat.com",
        })

        assert.equals(0, cjson.decode(res.body).status)
      end)

      it("should invalidate pending resets on success", function()
        local res = api_client_request({
          method = "POST",
          path = "/resend-account-verification",
          body = {
            email = unverified_developer.email
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(204, res.status)
        local pending_tokens = get_pending_tokens(db, unverified_developer)
        assert.equals(1, #pending_tokens)

        local claims = {id = unverified_developer.consumer.id, exp = time() + 100000}
        local valid_jwt = ee_jwt.generate_JWT(claims, secret)

        local res = api_client_request({
          method = "POST",
          path = "/verify-account",
          body = {
            token = valid_jwt,
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(401, res.status)

        local res = client_request({
          method = "GET",
          path = "/developers/" .. unverified_developer.email,
        })

        assert.equals(5, cjson.decode(res.body).status)
      end)

      it("should create valid reset on success", function()
        local res = api_client_request({
          method = "POST",
          path = "/resend-account-verification",
          body = {
            email = unverified_developer.email
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(204, res.status)
        local pending_tokens = get_pending_tokens(db, unverified_developer)
        assert.equals(1, #pending_tokens)
        local new_secret = pending_tokens[1].secret

        local claims = {id = unverified_developer.consumer.id, exp = time() + 100000}
        local valid_jwt = ee_jwt.generate_JWT(claims, new_secret)

        local res = api_client_request({
          method = "POST",
          path = "/verify-account",
          body = {
            token = valid_jwt,
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(200, res.status)

        local res = client_request({
          method = "GET",
          path = "/developers/" .. unverified_developer.email,
        })

        assert.equals(0, cjson.decode(res.body).status)
      end)
    end)

    describe("/invalidate-account-verification", function()
      local unverified_developer

      before_each(function()
        configure_portal(db, {
          portal = true,
          portal_auth = "basic-auth",
          portal_auto_approve = true,
        })

        local res = register_developer({
          email = "kongkong@konghq.com",
          password = "wowza",
          meta = "{\"full_name\":\"1337\"}",
        })

        assert.equals(200, res.status)
        local resp_body_json = cjson.decode(res.body)
        unverified_developer = resp_body_json.developer

        secret = get_pending_tokens(db, unverified_developer)[1].secret
      end)

      after_each(function()
        db:truncate()
      end)

      it("should return 400 if called without a token", function()
        local res = api_client_request({
          method = "POST",
          path = "/invalidate-account-verification",
          body = {
            token = "",
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(400, res.status)
        local resp_body_json = cjson.decode(res.body)
        local message = resp_body_json.message

        assert.equal("token is required", message)
        assert.equals(1, #get_pending_tokens(db, unverified_developer))
      end)

      it("should return 401 if called with an invalid jwt format", function()
        local res = api_client_request({
          method = "POST",
          path = "/invalidate-account-verification",
          body = {
            token = "im_a_token_lol",
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(401, res.status)
        local resp_body_json = cjson.decode(res.body)
        local message = resp_body_json.message

        assert.equal("Unauthorized", message)
        assert.equals(1, #get_pending_tokens(db, unverified_developer))
      end)

      it("should return 401 if token is signed with an invalid secret", function()
        local claims = {id = unverified_developer.consumer.id, exp = time() + 100000}
        local bad_jwt = ee_jwt.generate_JWT(claims, "bad_secret")

        local res = api_client_request({
          method = "POST",
          path = "/invalidate-account-verification",
          body = {
            token = bad_jwt,
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(401, res.status)
        local resp_body_json = cjson.decode(res.body)
        local message = resp_body_json.message

        assert.equal("Unauthorized", message)
        assert.equals(1, #get_pending_tokens(db, unverified_developer))
      end)


      it("should return 401 if token is expired", function()
        local claims = {id = unverified_developer.consumer.id, exp = time() - 100000}
        local expired_jwt = ee_jwt.generate_JWT(claims, secret)

        local res = api_client_request({
          method = "POST",
          path = "/invalidate-account-verification",
          body = {
            token = expired_jwt,
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(401, res.status)
        local resp_body_json = cjson.decode(res.body)
        local message = resp_body_json.message

        assert.equal("Unauthorized", message)
        assert.equals(1, #get_pending_tokens(db, unverified_developer))
      end)


      it("should return 401 if token contains non-existent developer", function()
        local claims = {id = uuid(), exp = time() + 100000}
        local random_uuid_jwt = ee_jwt.generate_JWT(claims, secret)

        local res = api_client_request({
          method = "POST",
          path = "/invalidate-account-verification",
          body = {
            token = random_uuid_jwt,
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(401, res.status)
        assert.equals(1, #get_pending_tokens(db, unverified_developer))
      end)

      it("should invalidate pending resets on success", function()
        local claims = {id = unverified_developer.consumer.id, exp = time() + 100000}
        local valid_jwt = ee_jwt.generate_JWT(claims, secret)

        api_client_request({
          method = "POST",
          path = "/invalidate-account-verification",
          body = {
            token = valid_jwt,
          },
          headers = {["Content-Type"] = "application/json"}
        })

        local res = api_client_request({
          method = "POST",
          path = "/verify-account",
          body = {
            token = valid_jwt,
          },
          headers = {["Content-Type"] = "application/json"}
        })

        assert.equals(401, res.status)

        local res = client_request({
          method = "GET",
          path = "/developers/" .. unverified_developer.email,
        })

        assert.equals(404, res.status)
      end)
    end)
  end)
end
