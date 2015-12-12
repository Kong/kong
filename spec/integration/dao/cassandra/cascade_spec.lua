local spec_helper = require "spec.spec_helpers"

local env = spec_helper.get_env()
local dao_factory = env.dao_factory

dao_factory:load_plugins({"keyauth", "basicauth", "oauth2"})

describe("Cassandra cascade delete", function()
  setup(function()
    spec_helper.prepare_db()
  end)
  describe("API -> plugins", function()
    local api, untouched_api

    setup(function()
      local fixtures = spec_helper.insert_fixtures {
        api = {
          {name = "cascade-delete",
           request_host = "mockbin.com",
           upstream_url = "http://mockbin.com"},
          {name = "untouched-cascade-delete",
           request_host = "untouched.com",
           upstream_url = "http://mockbin.com"}
        },
        plugin = {
          {name = "key-auth",                                    __api = 1},
          {name = "rate-limiting", config = {minute = 6},        __api = 1},
          {name = "file-log", config = {path = "/tmp/spec.log"}, __api = 1},
          {name = "key-auth",                                    __api = 2}
        }
      }
      api = fixtures.api[1]
      untouched_api = fixtures.api[2]
    end)
    teardown(function()
      spec_helper.drop_db()
    end)
    it("should delete foreign plugins when deleting an API", function()
      local ok, err = dao_factory.apis:delete(api)
      assert.falsy(err)
      assert.True(ok)

      -- Make sure we have 0 matches
      local results, err = dao_factory.plugins:find_by_keys {
        api_id = api.id
      }
      assert.falsy(err)
      assert.equal(0, #results)

      -- Make sure the untouched API still has its plugins
      results, err = dao_factory.plugins:find_by_keys {
        api_id = untouched_api.id
      }
      assert.falsy(err)
      assert.equal(1, #results)
    end)
  end)

  describe("Consumer -> plugins", function()
    local consumer, untouched_consumer

    setup(function()
      local fixtures = spec_helper.insert_fixtures {
        api = {
          {name = "cascade-delete",
           request_host = "mockbin.com",
           upstream_url = "http://mockbin.com"}
        },
        consumer = {
          {username = "king kong"},
          {username = "untouched consumer"}
        },
        plugin = {
          {name = "rate-limiting", config = {minute = 6},        __api = 1, __consumer = 1},
          {name = "response-transformer",                        __api = 1, __consumer = 1},
          {name = "file-log", config = {path = "/tmp/spec.log"}, __api = 1, __consumer = 1},
          {name = "request-transformer",                         __api = 1, __consumer = 2}
        }
      }
      consumer = fixtures.consumer[1]
      untouched_consumer = fixtures.consumer[2]
    end)
    teardown(function()
      spec_helper.drop_db()
    end)
    it("should delete foreign plugins when deleting a Consumer", function()
      local ok, err = dao_factory.consumers:delete(consumer)
      assert.falsy(err)
      assert.True(ok)

      local results, err = dao_factory.plugins:find_by_keys {
        consumer_id = consumer.id
      }
      assert.falsy(err)
      assert.equal(0, #results)

      -- Make sure the untouched Consumer still has its plugin
      results, err = dao_factory.plugins:find_by_keys {
        consumer_id = untouched_consumer.id
      }
      assert.falsy(err)
      assert.equal(1, #results)
    end)
  end)

  describe("Consumer -> keyauth_credentials", function()
    local consumer, untouched_consumer

    setup(function()
      local fixtures = spec_helper.insert_fixtures {
        consumer = {
          {username = "cascade_delete_consumer"},
          {username = "untouched_consumer"}
        },
        keyauth_credential = {
          {key = "apikey123", __consumer = 1},
          {key = "apikey456", __consumer = 2}
        }
      }
      consumer = fixtures.consumer[1]
      untouched_consumer = fixtures.consumer[2]
    end)
    teardown(function()
      spec_helper.drop_db()
    end)
    it("should delete foreign keyauth_credentials when deleting a Consumer", function()
      local ok, err = dao_factory.consumers:delete(consumer)
      assert.falsy(err)
      assert.True(ok)

      local results, err = dao_factory.keyauth_credentials:find_by_keys {
        consumer_id = consumer.id
      }
      assert.falsy(err)
      assert.equal(0, #results)

      results, err = dao_factory.keyauth_credentials:find_by_keys {
        consumer_id = untouched_consumer.id
      }
      assert.falsy(err)
      assert.equal(1, #results)
    end)
  end)

  describe("Consumer -> basicauth_credentials", function()
    local consumer, untouched_consumer

    setup(function()
      local fixtures = spec_helper.insert_fixtures {
        consumer = {
          {username = "cascade_delete_consumer"},
          {username = "untouched_consumer"}
        },
        basicauth_credential = {
          {username = "username", password = "password", __consumer = 1},
          {username = "username2", password = "password2", __consumer = 2}
        }
      }
      consumer = fixtures.consumer[1]
      untouched_consumer = fixtures.consumer[2]
    end)
    teardown(function()
      spec_helper.drop_db()
    end)
    it("should delete foreign basicauth_credentials when deleting a Consumer", function()
      local ok, err = dao_factory.consumers:delete(consumer)
      assert.falsy(err)
      assert.True(ok)

      local results, err = dao_factory.basicauth_credentials:find_by_keys {
        consumer_id = consumer.id
      }
      assert.falsy(err)
      assert.equal(0, #results)

      results, err = dao_factory.basicauth_credentials:find_by_keys {
        consumer_id = untouched_consumer.id
      }
      assert.falsy(err)
      assert.equal(1, #results)
    end)
  end)

  describe("Consumer -> oauth2_credentials -> oauth2_tokens", function()
    local consumer, untouched_consumer, credential

    setup(function()
      local fixtures = spec_helper.insert_fixtures {
        consumer = {
          {username = "cascade_delete_consumer"},
          {username = "untouched_consumer"}
        },
        oauth2_credential = {
          {client_id = "clientid123",
           client_secret = "secret123",
           redirect_uri = "http://google.com/kong",
           name = "testapp",
           __consumer = 1},
          {client_id = "clientid1232",
           client_secret = "secret1232",
           redirect_uri = "http://google.com/kong",
           name = "testapp",
           __consumer = 2}
        }
      }
      consumer = fixtures.consumer[1]
      untouched_consumer = fixtures.consumer[2]
      credential = fixtures.oauth2_credential[1]

      local _, err = dao_factory.oauth2_tokens:insert {
        credential_id = credential.id,
        authenticated_userid = consumer.id,
        expires_in = 100,
        scope = "email"
      }
      assert.falsy(err)
    end)
    teardown(function()
      spec_helper.drop_db()
    end)
    it("should delete foreign oauth2_credentials and tokens when deleting a Consumer", function()
      local ok, err = dao_factory.consumers:delete(consumer)
      assert.falsy(err)
      assert.True(ok)

      local results, err = dao_factory.oauth2_credentials:find_by_keys {
        consumer_id = consumer.id
      }
      assert.falsy(err)
      assert.equal(0, #results)

      results, err = dao_factory.oauth2_tokens:find_by_keys {
        credential_id = credential.id
      }
      assert.falsy(err)
      assert.equal(0, #results)

      results, err = dao_factory.oauth2_credentials:find_by_keys {
        consumer_id = untouched_consumer.id
      }
      assert.falsy(err)
      assert.equal(1, #results)
    end)
  end)
end)
