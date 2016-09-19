local helpers = require "spec.helpers"

describe('Plugin: ldap-acl consumer unit tests', function()
  local consumer1 = { username = 'consumer1' }
  local consumers
  setup(function()
    consumers = {
      [1] = consumer1
    }
  end)
  teardown(function()
    helpers.dao:truncate_tables()
  end)
  describe('should be find consumer from ldap user', function()
    it('retrieve a consumer by username', function()

      local dao = helpers.dao.consumers
      stub(dao, 'find_all').returns(consumers)

      local BindConsumer = require('kong.plugins.ldap-acl.bind_consumer')
      local bind_consumer = BindConsumer:new { dao = dao }

      local consumer = bind_consumer.bind(bind_consumer, 'consumer1')

      assert.is_not_nil(consumer)
      assert.are.equals(consumer1.username, consumer.username)
    end)
    it('failed on retrieve a consumer by username', function()

      local dao = helpers.dao.consumers
      stub(dao, 'find_all').returns({})

      local BindConsumer = require('kong.plugins.ldap-acl.bind_consumer')
      local bind_consumer = BindConsumer:new { dao = dao }

      local consumer = bind_consumer.bind(bind_consumer, 'no_bind')

      assert.is_nil(consumer)
    end)
  end)
end)