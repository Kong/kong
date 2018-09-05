local helpers = require "spec.helpers"
local Errors  = require "kong.db.errors"
local cluster_ca_tools = require "kong.tools.cluster_ca"


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    --[[
    -- CA
    --]]
    describe("kong.db.cluster_ca", function()
      local db
      local ca_key
      local ca_cert

      setup(function()
        local _
        _, db = helpers.get_db_utils(strategy, {
          "cluster_ca",
        })

        ca_key = cluster_ca_tools.new_key()
        ca_cert = cluster_ca_tools.new_ca(ca_key)
      end)

      before_each(function()
        assert(db:truncate("cluster_ca"))
      end)

      it(":insert() a cluster CA into empty DB", function()
        local ca, err, err_t = db.cluster_ca:insert({
          key = ca_key:toPEM("private"),
          cert = ca_cert:toPEM(),
        })
        assert.is_nil(err_t)
        assert.is_nil(err)
        assert.truthy(ca)
      end)

      it(":insert() fails when row already present", function()
        do
          local ca, err, err_t = db.cluster_ca:insert({
            key = ca_key:toPEM("private"),
            cert = ca_cert:toPEM(),
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.truthy(ca)
        end

        do
          local alt_ca_key = cluster_ca_tools.new_key()
          local alt_ca_cert = cluster_ca_tools.new_ca(alt_ca_key)
          local ca, _, err_t = db.cluster_ca:insert({
            key = alt_ca_key:toPEM("private"),
            cert = alt_ca_cert:toPEM(),
          })
          assert.falsy(ca)
          assert.same({
            strategy = strategy,
            code = Errors.codes.PRIMARY_KEY_VIOLATION,
            fields = {
              pk = true,
            },
            name = "primary key violation",
            message = [[primary key violation on key '{pk=true}']],
          }, err_t)
        end
      end)

      it(":select() returns nothing on empty table", function()
        local row, err, err_t = db.cluster_ca:select({ pk = true })
        assert.is_nil(err_t)
        assert.is_nil(err)
        assert.is_nil(row)
      end)

      it(":select() returns cert+key", function()
        local insert_row = {
          key = ca_key:toPEM("private"),
          cert = ca_cert:toPEM(),
        }
        assert.truthy(db.cluster_ca:insert(insert_row))
        insert_row.pk = true -- automatically added
        local row, err, err_t = db.cluster_ca:select({ pk = true })
        assert.is_nil(err_t)
        assert.is_nil(err)
        assert.same(insert_row, row)
      end)
    end)
  end)
end
