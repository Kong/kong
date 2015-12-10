local spec_helper = require "spec.spec_helpers"
local utils = require "kong.tools.utils"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"
local rex = require "rex_pcre"

-- Load everything we need from the spec_helper
local env = spec_helper.get_env() -- test environment
local dao_factory = env.dao_factory
local configuration = env.configuration
configuration.cassandra = configuration.databases_available[configuration.database].properties

local PROXY_SSL_URL = spec_helper.PROXY_SSL_URL
local PROXY_URL = spec_helper.PROXY_URL
local STUB_GET_URL = spec_helper.STUB_GET_URL
local STUB_POST_URL = spec_helper.STUB_POST_URL

local function provision_code()
  local response = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email", response_type = "code", state = "hello", authenticated_userid = "userid123" }, {host = "oauth2.com"})
  local body = cjson.decode(response)
  local matches = rex.gmatch(body.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
  local code
  for line in matches do
    code = line
  end
  local data = dao_factory.oauth2_authorization_codes:find_by_keys({code = code})
  return data[1].code
end

local function provision_token()
  local code = provision_code()

  local response = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
  return cjson.decode(response)
end

describe("Authentication Plugin", function()

  local function prepare()
    spec_helper.drop_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests-oauth2", request_host = "oauth2.com", upstream_url = "http://mockbin.com" },
        { name = "tests-oauth2-with-path", request_host = "mockbin-path.com", upstream_url = "http://mockbin.com", request_path = "/somepath/" },
        { name = "tests-oauth2-with-hide-credentials", request_host = "oauth2_3.com", upstream_url = "http://mockbin.com" },
        { name = "tests-oauth2-client-credentials", request_host = "oauth2_4.com", upstream_url = "http://mockbin.com" },
        { name = "tests-oauth2-password-grant", request_host = "oauth2_5.com", upstream_url = "http://mockbin.com" },
        { name = "tests-oauth2-accept_http_if_already_terminated", request_host = "oauth2_6.com", upstream_url = "http://mockbin.com" },
      },
      consumer = {
        { username = "auth_tests_consumer" }
      },
      plugin = {
        { name = "oauth2", config = { scopes = { "email", "profile", "user.email" }, mandatory_scope = true, provision_key = "provision123", token_expiration = 5, enable_implicit_grant = true }, __api = 1 },
        { name = "oauth2", config = { scopes = { "email", "profile" }, mandatory_scope = true, provision_key = "provision123", token_expiration = 5, enable_implicit_grant = true }, __api = 2 },
        { name = "oauth2", config = { scopes = { "email", "profile" }, mandatory_scope = true, provision_key = "provision123", token_expiration = 5, enable_implicit_grant = true, hide_credentials = true }, __api = 3 },
        { name = "oauth2", config = { scopes = { "email", "profile" }, mandatory_scope = true, provision_key = "provision123", token_expiration = 5, enable_client_credentials = true, enable_authorization_code = false }, __api = 4 },
        { name = "oauth2", config = { scopes = { "email", "profile" }, mandatory_scope = true, provision_key = "provision123", token_expiration = 5, enable_password_grant = true, enable_authorization_code = false }, __api = 5 },
        { name = "oauth2", config = { scopes = { "email", "profile", "user.email" }, mandatory_scope = true, provision_key = "provision123", token_expiration = 5, enable_implicit_grant = true, accept_http_if_already_terminated = true }, __api = 6 },
      },
      oauth2_credential = {
        { client_id = "clientid123", client_secret = "secret123", redirect_uri = "http://google.com/kong", name="testapp", __consumer = 1 }
      }
    }
  end

  setup(function()
    spec_helper.prepare_db()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  before_each(function()
    spec_helper.restart_kong() -- Required because the uuid function doesn't seed itself every millisecond, but every second
    prepare()
  end)

  describe("OAuth2 Authorization", function()

    describe("Code Grant", function()

      it("should return an error when no provision_key is being sent", function()
        local response, status, headers = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_provision_key", body.error)
        assert.are.equal("Invalid Kong provision_key", body.error_description)

        -- Checking headers
        assert.are.equal("no-store", headers["cache-control"])
        assert.are.equal("no-cache", headers["pragma"])
      end)

      it("should return an error when no parameter is being sent", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_authenticated_userid", body.error)
        assert.are.equal("Missing authenticated_userid parameter", body.error_description)
      end)

      it("should return an error when only provision_key and authenticated_userid are sent", function()
        local response, status, headers = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_request", body.error)
        assert.are.equal("Invalid client_id", body.error_description)

        -- Checking headers
        assert.are.equal("no-store", headers["cache-control"])
        assert.are.equal("no-cache", headers["pragma"])
      end)

      it("should return an error when only the client_is being sent", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(1, utils.table_size(body))
        assert.are.equal("http://google.com/kong?error=invalid_scope&error_description=You%20must%20specify%20a%20scope", body.redirect_uri)
      end)

      it("should return an error when an invalid scope is being sent", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "wot" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(1, utils.table_size(body))
        assert.are.equal("http://google.com/kong?error=invalid_scope&error_description=%22wot%22%20is%20an%20invalid%20scope", body.redirect_uri)
      end)

      it("should return an error when no response_type is being sent", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(1, utils.table_size(body))
        assert.are.equal("http://google.com/kong?error=unsupported_response_type&error_description=Invalid%20response_type", body.redirect_uri)
      end)

      it("should return an error with a state when no response_type is being sent", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email", state = "somestate" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(1, utils.table_size(body))
        assert.are.equal("http://google.com/kong?error=unsupported_response_type&state=somestate&error_description=Invalid%20response_type", body.redirect_uri)
      end)

      it("should return error when the redirect_uri does not match", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email", response_type = "code", redirect_uri = "http://hello.com/" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(1, utils.table_size(body))
        assert.are.equal("http://google.com/kong?error=invalid_request&error_description=Invalid%20redirect_uri%20that%20does%20not%20match%20with%20the%20one%20created%20with%20the%20application", body.redirect_uri)
      end)

      it("should fail when not under HTTPS", function()
        local response, status = http_client.post(PROXY_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email", response_type = "code" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("access_denied", body.error)
        assert.are.equal("You must use HTTPS", body.error_description)
      end)

      it("should work when not under HTTPS but accept_http_if_already_terminated is true", function()
        local response, status = http_client.post(PROXY_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email", response_type = "code" }, {host = "oauth2_6.com", ["X-Forwarded-Proto"] = "https"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equal(1, utils.table_size(body))
        assert.truthy(rex.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}$"))
      end)

      it("should fail when not under HTTPS and accept_http_if_already_terminated is false", function()
        local response, status = http_client.post(PROXY_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email", response_type = "code" }, {host = "oauth2.com", ["X-Forwarded-Proto"] = "https"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("access_denied", body.error)
        assert.are.equal("You must use HTTPS", body.error_description)
      end)

      it("should return success", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email", response_type = "code" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equal(1, utils.table_size(body))
        assert.truthy(rex.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}$"))
      end)

      it("should fail with a path when using the DNS", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123a", authenticated_userid = "id123", client_id = "clientid123", scope = "email", response_type = "code" }, {host = "mockbin-path.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_provision_key", body.error)
        assert.are.equal("Invalid Kong provision_key", body.error_description)
      end)

      it("should return success with a path", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/somepath/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email", response_type = "code" }, {host = "mockbin-path.com"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equal(1, utils.table_size(body))
        assert.truthy(rex.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}$"))
      end)

      it("should return success when requesting the url with final slash", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/authorize/", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email", response_type = "code" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equal(1, utils.table_size(body))
        assert.truthy(rex.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}$"))
      end)

      it("should return success with a state", function()
        local response, status, headers = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email", response_type = "code", state = "hello" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equal(1, utils.table_size(body))
        assert.truthy(rex.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}&state=hello$"))

        -- Checking headers
        assert.are.equal("no-store", headers["cache-control"])
        assert.are.equal("no-cache", headers["pragma"])
      end)

      it("should return success and store authenticated user properties", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email", response_type = "code", state = "hello", authenticated_userid = "userid123" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equal(1, utils.table_size(body))
        assert.truthy(rex.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}&state=hello$"))

        local matches = rex.gmatch(body.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
        local code
        for line in matches do
          code = line
        end
        local data = dao_factory.oauth2_authorization_codes:find_by_keys({code = code})
        assert.are.equal(1, #data)
        assert.are.equal(code, data[1].code)

        assert.are.equal("userid123", data[1].authenticated_userid)
        assert.are.equal("email", data[1].scope)
      end)

      it("should return success with a dotted scope and store authenticated user properties", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "user.email", response_type = "code", state = "hello", authenticated_userid = "userid123" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equal(1, utils.table_size(body))
        assert.truthy(rex.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}&state=hello$"))

        local matches = rex.gmatch(body.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
        local code
        for line in matches do
          code = line
        end
        local data = dao_factory.oauth2_authorization_codes:find_by_keys({code = code})
        assert.are.equal(1, #data)
        assert.are.equal(code, data[1].code)

        assert.are.equal("userid123", data[1].authenticated_userid)
        assert.are.equal("user.email", data[1].scope)
      end)

    end)

    describe("Implicit Grant", function()

      it("should return success", function()
        local response, status, headers = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email", response_type = "token" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equal(1, utils.table_size(body))
        assert.truthy(rex.match(body.redirect_uri, "^http://google\\.com/kong\\?token_type=bearer&access_token=[\\w]{32,32}$"))

        -- Checking headers
        assert.are.equal("no-store", headers["cache-control"])
        assert.are.equal("no-cache", headers["pragma"])
      end)
      it("should return success and the state", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email", response_type = "token", state = "wot" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equal(1, utils.table_size(body))
        assert.truthy(rex.match(body.redirect_uri, "^http://google\\.com/kong\\?token_type=bearer&state=wot&access_token=[\\w]{32,32}$"))
      end)

      it("should return success and store authenticated user properties", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email  profile", response_type = "token", authenticated_userid = "userid123" }, {host = "oauth2.com"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equal(1, utils.table_size(body))
        assert.truthy(rex.match(body.redirect_uri, "^http://google\\.com/kong\\?token_type=bearer&access_token=[\\w]{32,32}$"))

        local matches = rex.gmatch(body.redirect_uri, "^http://google\\.com/kong\\?token_type=bearer&access_token=([\\w]{32,32})$")
        local access_token
        for line in matches do
          access_token = line
        end
        local data = dao_factory.oauth2_tokens:find_by_keys({access_token = access_token})
        assert.are.equal(1, #data)
        assert.are.equal(access_token, data[1].access_token)

        assert.are.equal("userid123", data[1].authenticated_userid)
        assert.are.equal("email profile", data[1].scope)

        -- Checking that there is no refresh token since it's an implicit grant
        assert.are.equal(0, data[1].expires_in)
        assert.falsy(data[1].refresh_token)
      end)

      it("should return set the right upstream headers", function()
        local response = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", scope = "email  profile", response_type = "token", authenticated_userid = "userid123" }, {host = "oauth2.com"})
        local body = cjson.decode(response)

        local matches = rex.gmatch(body.redirect_uri, "^http://google\\.com/kong\\?token_type=bearer&access_token=([\\w]{32,32})$")
        local access_token
        for line in matches do
          access_token = line
        end

        local response, status = http_client.get(PROXY_SSL_URL.."/request", { access_token = access_token }, {host = "oauth2.com"})
        assert.are.equal(200, status)

        local body = cjson.decode(response)
        assert.truthy(body.headers["x-consumer-id"])
        assert.are.equal("auth_tests_consumer", body.headers["x-consumer-username"])
        assert.are.equal("email profile", body.headers["x-authenticated-scope"])
        assert.are.equal("userid123", body.headers["x-authenticated-userid"])
      end)

    end)

    describe("Client Credentials", function()

      it("should return an error when client_secret is not sent", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { client_id = "clientid123", scope = "email", response_type = "token" }, {host = "oauth2_4.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_request", body.error)
        assert.are.equal("Invalid client_secret", body.error_description)
      end)

      it("should return an error when client_secret is not sent", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { client_id = "clientid123", client_secret="secret123", scope = "email", response_type = "token" }, {host = "oauth2_4.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_request", body.error)
        assert.are.equal("Invalid grant_type", body.error_description)
      end)

      it("should fail when not under HTTPS", function()
        local response, status = http_client.post(PROXY_URL.."/oauth2/token", { client_id = "clientid123", client_secret="secret123", scope = "email", grant_type = "client_credentials" }, {host = "oauth2_4.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("access_denied", body.error)
        assert.are.equal("You must use HTTPS", body.error_description)
      end)

      it("should return fail when setting authenticated_userid and no provision_key", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { client_id = "clientid123", client_secret="secret123", scope = "email", grant_type = "client_credentials", authenticated_userid = "user123" }, {host = "oauth2_4.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_provision_key", body.error)
        assert.are.equal("Invalid Kong provision_key", body.error_description)
      end)

      it("should return fail when setting authenticated_userid and invalid provision_key", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { client_id = "clientid123", client_secret="secret123", scope = "email", grant_type = "client_credentials", authenticated_userid = "user123", provision_key = "hello" }, {host = "oauth2_4.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_provision_key", body.error)
        assert.are.equal("Invalid Kong provision_key", body.error_description)
      end)

      it("should return success", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { client_id = "clientid123", client_secret="secret123", scope = "email", grant_type = "client_credentials" }, {host = "oauth2_4.com"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equals(3, utils.table_size(body))
        assert.falsy(body.refresh_token)
        assert.truthy(body.access_token)
        assert.are.equal("bearer", body.token_type)
        assert.are.equal(5, body.expires_in)
      end)

      it("should return success with authenticated_userid and valid provision_key", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { client_id = "clientid123", client_secret="secret123", scope = "email", grant_type = "client_credentials", authenticated_userid = "hello", provision_key = "provision123" }, {host = "oauth2_4.com"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equals(3, utils.table_size(body))
        assert.falsy(body.refresh_token)
        assert.truthy(body.access_token)
        assert.are.equal("bearer", body.token_type)
        assert.are.equal(5, body.expires_in)
      end)

      it("should return success with authorization header", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { scope = "email", grant_type = "client_credentials" }, {host = "oauth2_4.com", authorization = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTIz"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equals(3, utils.table_size(body))
        assert.falsy(body.refresh_token)
        assert.truthy(body.access_token)
        assert.are.equal("bearer", body.token_type)
        assert.are.equal(5, body.expires_in)
      end)

      it("should return an error with a wrong authorization header", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { scope = "email", grant_type = "client_credentials" }, {host = "oauth2_4.com", authorization = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTI0"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_request", body.error)
        assert.are.equal("Invalid client_secret", body.error_description)
      end)

      it("should return set the right upstream headers", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { client_id = "clientid123", client_secret="secret123", scope = "email", grant_type = "client_credentials", authenticated_userid = "hello", provision_key = "provision123" }, {host = "oauth2_4.com"})
        assert.are.equal(200, status)

        local response, status = http_client.get(PROXY_SSL_URL.."/request", { access_token = cjson.decode(response).access_token }, {host = "oauth2_4.com"})
        assert.are.equal(200, status)

        local body = cjson.decode(response)
        assert.truthy(body.headers["x-consumer-id"])
        assert.are.equal("auth_tests_consumer", body.headers["x-consumer-username"])
        assert.are.equal("email", body.headers["x-authenticated-scope"])
        assert.are.equal("hello", body.headers["x-authenticated-userid"])
      end)

    end)

    describe("Password Grant", function()

      it("should return an error when client_secret is not sent", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { client_id = "clientid123", scope = "email", response_type = "token" }, {host = "oauth2_5.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_request", body.error)
        assert.are.equal("Invalid client_secret", body.error_description)
      end)

      it("should return an error when client_secret is not sent", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { client_id = "clientid123", client_secret="secret123", scope = "email", response_type = "token" }, {host = "oauth2_5.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_request", body.error)
        assert.are.equal("Invalid grant_type", body.error_description)
      end)

      it("should fail when no provision key is being sent", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { client_id = "clientid123", client_secret="secret123", scope = "email", grant_type = "password" }, {host = "oauth2_5.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_provision_key", body.error)
        assert.are.equal("Invalid Kong provision_key", body.error_description)
      end)

      it("should fail when no provision key is being sent", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { client_id = "clientid123", client_secret="secret123", scope = "email", grant_type = "password" }, {host = "oauth2_5.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_provision_key", body.error)
        assert.are.equal("Invalid Kong provision_key", body.error_description)
      end)

      it("should fail when no authenticated user id is being sent", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { provision_key = "provision123", client_id = "clientid123", client_secret="secret123", scope = "email", grant_type = "password" }, {host = "oauth2_5.com"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_authenticated_userid", body.error)
        assert.are.equal("Missing authenticated_userid parameter", body.error_description)
      end)

      it("should return success", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { provision_key = "provision123", authenticated_userid = "id123", client_id = "clientid123", client_secret="secret123", scope = "email", grant_type = "password" }, {host = "oauth2_5.com"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equals(4, utils.table_size(body))
        assert.truthy(body.refresh_token)
        assert.truthy(body.access_token)
        assert.are.equal("bearer", body.token_type)
        assert.are.equal(5, body.expires_in)
      end)

      it("should return success with authorization header", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { provision_key = "provision123", authenticated_userid = "id123", scope = "email", grant_type = "password" }, {host = "oauth2_5.com", authorization = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTIz"})
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.are.equals(4, utils.table_size(body))
        assert.truthy(body.refresh_token)
        assert.truthy(body.access_token)
        assert.are.equal("bearer", body.token_type)
        assert.are.equal(5, body.expires_in)
      end)

      it("should return an error with a wrong authorization header", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { provision_key = "provision123", authenticated_userid = "id123", scope = "email", grant_type = "password" }, {host = "oauth2_5.com", authorization = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTI0"})
        local body = cjson.decode(response)
        assert.are.equal(400, status)
        assert.are.equal(2, utils.table_size(body))
        assert.are.equal("invalid_request", body.error)
        assert.are.equal("Invalid client_secret", body.error_description)
      end)

      it("should return set the right upstream headers", function()
        local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { provision_key = "provision123", authenticated_userid = "id123", scope = "email", grant_type = "password" }, {host = "oauth2_5.com", authorization = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTIz"})
        assert.are.equal(200, status)

        local response, status = http_client.get(PROXY_SSL_URL.."/request", { access_token = cjson.decode(response).access_token }, {host = "oauth2_5.com"})
        assert.are.equal(200, status)

        local body = cjson.decode(response)
        assert.truthy(body.headers["x-consumer-id"])
        assert.are.equal("auth_tests_consumer", body.headers["x-consumer-username"])
        assert.are.equal("email", body.headers["x-authenticated-scope"])
        assert.are.equal("id123", body.headers["x-authenticated-userid"])
      end)

    end)

  end)

  describe("OAuth2 Access Token", function()

    it("should return an error when nothing is being sent", function()
      local response, status, headers = http_client.post(PROXY_SSL_URL.."/oauth2/token", { }, {host = "oauth2.com"})
      local body = cjson.decode(response)
      assert.are.equal(400, status)
      assert.are.equal(2, utils.table_size(body))
      assert.are.equal("invalid_request", body.error)
      assert.are.equal("Invalid client_id", body.error_description)

      -- Checking headers
      assert.are.equal("no-store", headers["cache-control"])
      assert.are.equal("no-cache", headers["pragma"])
    end)

    it("should return an error when only the code is being sent", function()
      local code = provision_code()

      local response, status, headers = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code }, {host = "oauth2.com"})
      local body = cjson.decode(response)
      assert.are.equal(400, status)
      assert.are.equal(2, utils.table_size(body))
      assert.are.equal("invalid_request", body.error)
      assert.are.equal("Invalid client_id", body.error_description)

      -- Checking headers
      assert.are.equal("no-store", headers["cache-control"])
      assert.are.equal("no-cache", headers["pragma"])
    end)

    it("should return an error when only the code and client_secret are being sent", function()
      local code = provision_code()

      local response, status, headers = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_secret = "secret123" }, {host = "oauth2.com"})
      local body = cjson.decode(response)
      assert.are.equal(400, status)
      assert.are.equal(2, utils.table_size(body))
      assert.are.equal("invalid_request", body.error)
      assert.are.equal("Invalid client_id", body.error_description)

      -- Checking headers
      assert.are.equal("no-store", headers["cache-control"])
      assert.are.equal("no-cache", headers["pragma"])
    end)

    it("should return an error when only the code and client_secret and client_id are being sent", function()
      local code = provision_code()

      local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "clientid123", client_secret = "secret123" }, {host = "oauth2.com"})
      local body = cjson.decode(response)
      assert.are.equal(400, status)
      assert.are.equal(2, utils.table_size(body))
      assert.are.equal("invalid_request", body.error)
      assert.are.equal("Invalid grant_type", body.error_description)
    end)

    it("should return an error with a wrong code", function()
      local code = provision_code()

      local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code.."hello", client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
      local body = cjson.decode(response)
      assert.are.equal(400, status)
      assert.are.equal(2, utils.table_size(body))
      assert.are.equal("invalid_request", body.error)
      assert.are.equal("Invalid code", body.error_description)
    end)

    it("should return success without state", function()
      local code = provision_code()

      local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equals(4, utils.table_size(body))
      assert.truthy(body.refresh_token)
      assert.truthy(body.access_token)
      assert.are.equal("bearer", body.token_type)
      assert.are.equal(5, body.expires_in)
    end)

    it("should return success with state", function()
      local code = provision_code()

      local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code", state = "wot" }, {host = "oauth2.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equals(5, utils.table_size(body))
      assert.truthy(body.refresh_token)
      assert.truthy(body.access_token)
      assert.are.equal("bearer", body.token_type)
      assert.are.equal(5, body.expires_in)
      assert.are.equal("wot", body.state)
    end)

    it("should return set the right upstream headers", function()
      local code = provision_code()
      local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
      assert.are.equal(200, status)

      local response, status = http_client.get(PROXY_SSL_URL.."/request", { access_token = cjson.decode(response).access_token }, {host = "oauth2.com"})
      assert.are.equal(200, status)

      local body = cjson.decode(response)
      assert.truthy(body.headers["x-consumer-id"])
      assert.are.equal("auth_tests_consumer", body.headers["x-consumer-username"])
      assert.are.equal("email", body.headers["x-authenticated-scope"])
      assert.are.equal("userid123", body.headers["x-authenticated-userid"])
    end)
  end)

  describe("Making a request", function()
    it("should work when a correct access_token is being sent in the querystring", function()
      local token = provision_token()
      local _, status = http_client.post(STUB_GET_URL, { access_token = token.access_token }, {host = "oauth2.com"})
      assert.are.equal(200, status)
    end)

    it("should work when a correct access_token is being sent in a form body", function()
      local token = provision_token()
      local _, status = http_client.post(STUB_POST_URL, { access_token = token.access_token }, {host = "oauth2.com"})
      assert.are.equal(200, status)
    end)

    it("should work when a correct access_token is being sent in an authorization header (bearer)", function()
      local token = provision_token()
      local _, status = http_client.post(STUB_POST_URL, { }, {host = "oauth2.com", authorization = "bearer "..token.access_token})
      assert.are.equal(200, status)
    end)

    it("should work when a correct access_token is being sent in an authorization header (token)", function()
      local token = provision_token()
      local response, status = http_client.post(STUB_POST_URL, { }, {host = "oauth2.com", authorization = "token "..token.access_token})
      local body = cjson.decode(response)
      assert.are.equal(200, status)

      local consumer = dao_factory.consumers:find_by_keys({username = "auth_tests_consumer"})[1]

      assert.are.equal(consumer.id, body.headers["x-consumer-id"])
      assert.are.equal(consumer.username, body.headers["x-consumer-username"])
      assert.are.equal("userid123", body.headers["x-authenticated-userid"])
      assert.are.equal("email", body.headers["x-authenticated-scope"])
    end)
  end)

  describe("Authentication challenge", function()
    it("should return 401 Unauthorized without error if it lacks any authentication information", function()
      local response, status, headers = http_client.post(STUB_GET_URL, { }, {host = "oauth2.com"})
      local body = cjson.decode(response)
      assert.are.equal(401, status)
      assert.are.equal('Bearer realm="service"', headers['www-authenticate'])
      assert.are.equal(0, utils.table_size(body))
    end)

    it("should return 401 Unauthorized when an invalid access token is being sent via url parameter", function()
      local response, status, headers = http_client.get(STUB_GET_URL, { access_token = "invalid" }, {host = "oauth2.com"})
      local body = cjson.decode(response)
      assert.are.equal(401, status)
      assert.are.equal('Bearer realm="service" error="invalid_token" error_description="The access token is invalid"', headers['www-authenticate'])
      assert.are.equal("invalid_token", body.error)
      assert.are.equal("The access token is invalid", body.error_description)
    end)

    it("should return 401 Unauthorized when an invalid access token is being sent via the Authorization header", function()
      local response, status, headers = http_client.post(STUB_POST_URL, { }, {host = "oauth2.com", authorization = "bearer invalid"})
      local body = cjson.decode(response)
      assert.are.equal(401, status)
      assert.are.equal('Bearer realm="service" error="invalid_token" error_description="The access token is invalid"', headers['www-authenticate'])
      assert.are.equal("invalid_token", body.error)
      assert.are.equal("The access token is invalid", body.error_description)
    end)

    it("should return 401 Unauthorized when token has expired", function()
      local token = provision_token()

      -- Token expires in (5 seconds)
      os.execute("sleep "..tonumber(6))

      local response, status, headers = http_client.post(STUB_POST_URL, { }, {host = "oauth2.com", authorization = "bearer "..token.access_token})
      local body = cjson.decode(response)
      assert.are.equal(401, status)
      assert.are.equal(2, utils.table_size(body))
      assert.are.equal('Bearer realm="service" error="invalid_token" error_description="The access token expired"', headers['www-authenticate'])
      assert.are.equal("invalid_token", body.error)
      assert.are.equal("The access token expired", body.error_description)
    end)
  end)

  describe("Refresh Token", function()

    it("should not refresh an invalid access token", function()
      local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { refresh_token = "hello", client_id = "clientid123", client_secret = "secret123", grant_type = "refresh_token" }, {host = "oauth2.com"})
      local body = cjson.decode(response)
      assert.are.equal(400, status)
      assert.are.equal(2, utils.table_size(body))
      assert.are.equal("invalid_request", body.error)
      assert.are.equal("Invalid refresh_token", body.error_description)
    end)

    it("should refresh an valid access token", function()
      local token = provision_token()
      local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { refresh_token = token.refresh_token, client_id = "clientid123", client_secret = "secret123", grant_type = "refresh_token" }, {host = "oauth2.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equals(4, utils.table_size(body))
      assert.truthy(body.refresh_token)
      assert.truthy(body.access_token)
      assert.are.equal("bearer", body.token_type)
      assert.are.equal(5, body.expires_in)
    end)

    it("should expire after 5 seconds", function()
      local token = provision_token()
      local _, status = http_client.post(STUB_POST_URL, { }, {host = "oauth2.com", authorization = "bearer "..token.access_token})
      assert.are.equal(200, status)

      local id = dao_factory.oauth2_tokens:find_by_keys({access_token = token.access_token })[1].id
      assert.truthy(dao_factory.oauth2_tokens:find_by_primary_key({id=id}))

      -- But waiting after the cache expiration (5 seconds) should block the request
      os.execute("sleep "..tonumber(6))

      local response, status = http_client.post(STUB_POST_URL, { }, {host = "oauth2.com", authorization = "bearer "..token.access_token})
      local body = cjson.decode(response)
      assert.are.equal(401, status)
      assert.are.equal("The access token expired", body.error_description)

      -- Refreshing the token
      local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { refresh_token = token.refresh_token, client_id = "clientid123", client_secret = "secret123", grant_type = "refresh_token" }, {host = "oauth2.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal(4, utils.table_size(body))
      assert.truthy(body.refresh_token)
      assert.truthy(body.access_token)
      assert.are.equal("bearer", body.token_type)
      assert.are.equal(5, body.expires_in)

      assert.falsy(token.access_token == body.access_token)
      assert.falsy(token.refresh_token == body.refresh_token)

      assert.falsy(dao_factory.oauth2_tokens:find_by_primary_key({id=id}))
    end)

  end)

  describe("Hide Credentials", function()

    it("should not hide credentials in the body", function()
      local token = provision_token()
      local response, status = http_client.post(STUB_POST_URL, { access_token = token.access_token }, {host = "oauth2.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal(token.access_token, body.postData.params.access_token)
    end)

    it("should hide credentials in the body", function()
      local token = provision_token()
      local response, status = http_client.post(STUB_POST_URL, { access_token = token.access_token }, {host = "oauth2_3.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.falsy(body.postData.params.access_token)
    end)

    it("should not hide credentials in the querystring", function()
      local token = provision_token()
      local response, status = http_client.get(STUB_GET_URL, { access_token = token.access_token }, {host = "oauth2.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal(token.access_token, body.queryString.access_token)
    end)

    it("should hide credentials in the querystring", function()
      local token = provision_token()
      local response, status = http_client.get(STUB_GET_URL, { access_token = token.access_token }, {host = "oauth2_3.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.falsy(body.queryString.access_token)
    end)

    it("should not hide credentials in the header", function()
      local token = provision_token()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "oauth2.com", authorization = "bearer "..token.access_token})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("bearer "..token.access_token, body.headers.authorization)
    end)

    it("should hide credentials in the header", function()
      local token = provision_token()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "oauth2_3.com", authorization = "bearer "..token.access_token})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.falsy(body.headers.authorization)
    end)

  end)

end)
