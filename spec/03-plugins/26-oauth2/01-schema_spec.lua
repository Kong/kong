local helpers         = require "spec.helpers"
local validate_entity = require("kong.dao.schemas_validation").validate_entity
local oauth2_daos     = require "kong.plugins.oauth2.daos"
local utils           = require "kong.tools.utils"

local oauth2_schema   = require "kong.plugins.oauth2.schema"

local oauth2_authorization_codes_schema = oauth2_daos.oauth2_authorization_codes
local oauth2_tokens_schema              = oauth2_daos.oauth2_tokens


local fmt = string.format


for _, strategy in helpers.each_strategy() do
  describe(fmt("Plugin: oauth2 [#%s] (schema)", strategy), function()
    local bp, db, dao = helpers.get_db_utils(strategy)

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
      auth_header_name = "custom_header_name"}
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
        local service = bp.services:insert()
        local u = utils.uuid()

        local ok, err, err_t = validate_entity({
          credential_id = "foo", expires_in = 1,
          service_id = "bar",
        }, oauth2_tokens_schema, { dao = dao })
        assert.False(ok)
        assert.is_nil(err)
        assert.equals(err_t.tbl.fields.id, "expected a valid UUID")

        local ok, err, err_t = validate_entity({
          credential_id = "foo", expires_in = 1,
          service_id = u,
        }, oauth2_tokens_schema, { dao = dao })
        assert.False(ok)
        assert.is_nil(err)
        assert.equals(err_t.message, fmt("no such Service (id=%s)", u))

        local ok, err, err_t = validate_entity({
          credential_id = "foo", expires_in = 1,
          service_id = service.id,
        }, oauth2_tokens_schema, { dao = dao })

        assert.True(ok)
        assert.is_nil(err)
        assert.is_nil(err_t)
      end)

      it("errors when given an invalid service_id on oauth authorization codes", function()
        local service = bp.services:insert()
        local u = utils.uuid()

        local ok, err, err_t = validate_entity({
          credential_id = "foo",
          service_id = "bar",
        }, oauth2_authorization_codes_schema, { dao = dao })
        assert.False(ok)
        assert.is_nil(err)
        assert.equals(err_t.tbl.fields.id, "expected a valid UUID")

        local ok, err, err_t = validate_entity({
          credential_id = "foo",
          service_id = u,
        }, oauth2_authorization_codes_schema, { dao = dao })
        assert.False(ok)
        assert.is_nil(err)
        assert.equals(err_t.message, fmt("no such Service (id=%s)", u))

        local ok, err, err_t = validate_entity({
          credential_id = "foo",
          service_id = service.id,
        }, oauth2_authorization_codes_schema, { dao = dao })

        assert.True(ok)
        assert.is_nil(err)
        assert.is_nil(err_t)
      end)
    end)

    describe("when deleting a service", function()
      it("deletes associated oauth2 entities", function()
        local service = bp.services:insert()
        local consumer = bp.consumers:insert()
        local credential = bp.oauth2_credentials:insert({
          redirect_uri = "http://example.com",
          consumer_id = consumer.id,
        })

        local ok, err, err_t

        local token = bp.oauth2_tokens:insert({
          credential_id = credential.id,
          service_id = service.id,
        })
        local code = bp.oauth2_authorization_codes:insert({
          credential_id = credential.id,
          service_id = service.id,
        })

        token, err = dao.oauth2_tokens:find(token)
        assert.falsy(err)
        assert.truthy(token)

        code, err = dao.oauth2_authorization_codes:find(code)
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
        token, err = dao.oauth2_tokens:find({ id = token.id })
        assert.falsy(err)
        assert.falsy(token)

        -- no more code
        local code, err = dao.oauth2_authorization_codes:find({ id = code.id })
        assert.falsy(err)
        assert.falsy(code)
      end)
    end)
  end)
end
