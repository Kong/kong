local spec_helper = require "spec.spec_helpers"
local uuid = require "uuid"

local env = spec_helper.get_env()
local dao_factory = env.dao_factory
local faker = env.faker

describe("DAO jwtauth Credentials", function()

  setup(function()
    spec_helper.prepare_db()
  end)

  it("should not insert in DB if consumer does not exist", function()
    -- Without a consumer_id, it's a schema error
    local app_t = {name = "jwtauth", value = {id_names = {"id"}}}
    local app, err = dao_factory.jwtauth_credentials:insert(app_t)
    assert.falsy(app)
    assert.truthy(err)
    assert.True(err.schema)
    assert.are.same("consumer_id is required", err.message.consumer_id)

    -- With an invalid consumer_id, it's a FOREIGN error
    local app_t = {secret = "secretkey123", consumer_id = uuid()}
    local app, err = dao_factory.jwtauth_credentials:insert(app_t)
    assert.falsy(app)
    assert.truthy(err)
    assert.True(err.foreign)
    assert.equal("consumer_id "..app_t.consumer_id.." does not exist", err.message.consumer_id)
  end)

  it("should insert in DB and add generated values", function()
    local consumer_t = faker:fake_entity("consumer")
    local consumer, err = dao_factory.consumers:insert(consumer_t)
    assert.falsy(err)

    local cred_t = {secret = "secretkey123", consumer_id = consumer.id}
    local app, err = dao_factory.jwtauth_credentials:insert(cred_t)
    assert.falsy(err)
    assert.truthy(app.id)
    assert.truthy(app.created_at)
  end)

  it("should find a Credential by public_key", function()
    local app, err = dao_factory.jwtauth_credentials:find_by_keys {
      secret = "user122"
    }
    assert.falsy(err)
    assert.truthy(app)
  end)

  it("should handle empty strings", function()
    local apps, err = dao_factory.jwtauth_credentials:find_by_keys {
      secret = ""
    }
    assert.falsy(err)
    assert.same({}, apps)
  end)

end)
