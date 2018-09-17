local helpers         = require "spec.helpers"
local validate_entity = require("kong.dao.schemas_validation").validate_entity
local utils           = require "kong.tools.utils"

local oauth2_schema   = require "kong.plugins.oauth2.schema"
local fmt = string.format

for _, strategy in helpers.each_strategy() do

  describe(fmt("Plugin: oauth2 [#%s] (schema)", strategy), function()
    local bp, db = helpers.get_db_utils(strategy)

    local oauth2_authorization_codes_schema = db.oauth2_authorization_codes.schema
    local oauth2_tokens_schema = db.oauth2_tokens.schema

    it("does not require `scopes` when `mandatory_scope` is false", function()
      local ok, errors = validate_entity({enable_authorization_code = true, mandatory_scope = false}, oauth2_schema)
      assert.True(ok)
      assert.is_nil(errors)
    end)
    it("valid when both `scopes` when `mandatory_scope` are given", function()
      local ok, errors = validate_entity({enable_authorization_code = true, mandatory_scope = true, scopes = {"email", "info"}}, oauth2_schema)
      assert.True(ok)
      assert.is_nil(errors)
    end)
    it("autogenerates `provision_key` when not given", function()
      local t = {enable_authorization_code = true, mandatory_scope = true, scopes = {"email", "info"}}
      local ok, errors = validate_entity(t, oauth2_schema)
      assert.True(ok)
      assert.is_nil(errors)
      assert.truthy(t.provision_key)
      assert.equal(32, t.provision_key:len())
    end)
    it("does not autogenerate `provision_key` when it is given", function()
      local t = {enable_authorization_code = true, mandatory_scope = true, scopes = {"email", "info"}, provision_key = "hello"}
      local ok, errors = validate_entity(t, oauth2_schema)
      assert.True(ok)
      assert.is_nil(errors)
      assert.truthy(t.provision_key)
      assert.equal("hello", t.provision_key)
    end)
    it("sets default `auth_header_name` when not given", function()
      local t = {enable_authorization_code = true, mandatory_scope = true, scopes = {"email", "info"}}
      local ok, errors = validate_entity(t, oauth2_schema)
      assert.True(ok)
      assert.is_nil(errors)
      assert.truthy(t.provision_key)
      assert.equal(32, t.provision_key:len())
      assert.equal("authorization", t.auth_header_name)
    end)
    it("does not set default value for `auth_header_name` when it is given", function()
      local t = {enable_authorization_code = true, mandatory_scope = true, scopes = {"email", "info"}, provision_key = "hello",
      auth_header_name="custom_header_name"}
      local ok, errors = validate_entity(t, oauth2_schema)
      assert.True(ok)
      assert.is_nil(errors)
      assert.truthy(t.provision_key)
      assert.equal("hello", t.provision_key)
      assert.equal("custom_header_name", t.auth_header_name)
    end)
    it("sets refresh_token_ttl to default value if not set", function()
      local t = {enable_authorization_code = true, mandatory_scope = false}
      local ok, errors = validate_entity(t, oauth2_schema)
      assert.True(ok)
      assert.is_nil(errors)
      assert.equal(1209600, t.refresh_token_ttl)
    end)

    describe("errors", function()
      it("requires at least one flow", function()
        local ok, _, err = validate_entity({}, oauth2_schema)
        assert.False(ok)
        assert.equal("You need to enable at least one OAuth flow", tostring(err))
      end)
      it("requires `scopes` when `mandatory_scope` is true", function()
        local ok, errors = validate_entity({enable_authorization_code = true, mandatory_scope = true}, oauth2_schema)
        assert.False(ok)
        assert.equal("To set a mandatory scope you also need to create available scopes", errors.mandatory_scope)
      end)
      it("errors when given an invalid service_id on oauth tokens", function()
        local ok, err_t = oauth2_tokens_schema:validate_insert({
          credential = { id = "foo" },
          service = { id = "bar" },
          expires_in = 1,
        })
        assert.falsy(ok)
        assert.same({
          credential = { id = 'expected a valid UUID' },
          service = { id = 'expected a valid UUID' },
          token_type = "required field missing",
        }, err_t)

        local ok, err_t = oauth2_tokens_schema:validate_insert({
          credential = { id = "foo" },
          service = { id = utils.uuid() },
          expires_in = 1,
        })
        assert.falsy(ok)
        assert.same({
          credential = { id = 'expected a valid UUID' },
          token_type = "required field missing",
        }, err_t)


        local ok, err_t = oauth2_tokens_schema:validate_insert({
          credential = { id = utils.uuid() },
          service = { id = utils.uuid() },
          expires_in = 1,
          token_type = "bearer",
        })

        assert.is_truthy(ok)
        assert.is_nil(err_t)
      end)

      it("#errors when given an invalid service_id on oauth authorization codes", function()
        local ok, err_t = oauth2_authorization_codes_schema:validate_insert({
          credential = { id = "foo" },
          service = { id = "bar" },
        })
        assert.falsy(ok)
        assert.same({
          credential = { id = 'expected a valid UUID' },
          service = { id = 'expected a valid UUID' },
        }, err_t)

        local ok, err_t = oauth2_authorization_codes_schema:validate_insert({
          credential = { id = "foo" },
          service = { id = utils.uuid() },
        })
        assert.falsy(ok)
        assert.same({
          credential = { id = 'expected a valid UUID' },
        }, err_t)

        local ok, err_t = oauth2_authorization_codes_schema:validate_insert({
          credential = { id = utils.uuid() },
          service = { id = utils.uuid() },
        })

        assert.truthy(ok)
        assert.is_nil(err_t)
      end)
    end)

    describe("when deleting a service", function()
      it("deletes associated oauth2 entities", function()
        local service = bp.services:insert()
        local consumer = bp.consumers:insert()
        local credential = bp.oauth2_credentials:insert({
          redirect_uris = { "http://example.com" },
          consumer = { id = consumer.id },
        })

        local ok, err, err_t

        local token = bp.oauth2_tokens:insert({
          credential = { id = credential.id },
          service = { id = service.id },
        })
        local code = bp.oauth2_authorization_codes:insert({
          credential = { id = credential.id },
          service = { id = service.id },
        })

        token, err = db.oauth2_tokens:select({ id = token.id })
        assert.falsy(err)
        assert.truthy(token)

        code, err = db.oauth2_authorization_codes:select({ id = code.id })
        assert.falsy(err)
        assert.truthy(code)

        ok, err, err_t = db.services:delete({ id = service.id })
        assert.truthy(ok)
        assert.is_nil(err_t)
        assert.is_nil(err)

        -- no more service
        service, err = db.services:select({ id = service.id })
        assert.falsy(err)
        assert.falsy(service)

        -- no more token
        token, err = db.oauth2_tokens:select({ id = token.id })
        assert.falsy(err)
        assert.falsy(token)

        -- no more code
        code, err = db.oauth2_authorization_codes:select({ id = code.id })
        assert.falsy(err)
        assert.falsy(code)
      end)
    end)
  end)
end
