local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local db


    lazy_setup(function()
      local _
      _, db, _ = helpers.get_db_utils(strategy, {})

      assert(db.connector:setup_locks(60))
    end)


    before_each(function()
      ngx.shared.kong_locks:flush_all()
      ngx.shared.kong_locks:flush_expired()
    end)


    describe("db:cluster_mutex()", function()
      it("returns 'true' when mutex ran and 'false' otherwise", function()
        local t1 = ngx.thread.spawn(function()
          local ok, err = db:cluster_mutex("my_key", nil, function()
            ngx.sleep(0.1)
          end)
          assert.is_nil(err)
          assert.equal(true, ok)
        end)

        local t2 = ngx.thread.spawn(function()
          local ok, err = db:cluster_mutex("my_key", nil, function() end)
          assert.is_nil(err)
          assert.equal(false, ok)
        end)

        ngx.thread.wait(t1)
        ngx.thread.wait(t2)
      end)


      it("mutex ensures only one callback gets called", function()
        local cb1 = spy.new(function() end)
        local cb2 = spy.new(function() ngx.sleep(0.3) end)

        local t1 = ngx.thread.spawn(function()
          ngx.sleep(0.2)

          local _, err = db:cluster_mutex("my_key_2", { owner = "1" }, cb1)
          assert.is_nil(err)
        end)

        local t2 = ngx.thread.spawn(function()
          local _, err = db:cluster_mutex("my_key_2", { owner = "2" }, cb2)
          assert.is_nil(err)
        end)

        ngx.thread.wait(t1)
        ngx.thread.wait(t2)

        assert.spy(cb2).was_called()
        assert.spy(cb1).was_not_called()
      end)


      it("mutex can be subsequently acquired once released", function()
        local cb1 = spy.new(function() end)
        local cb2 = spy.new(function() end)

        local t1 = ngx.thread.spawn(function()
          local _, err = db:cluster_mutex("my_key_3", nil, cb1)
          assert.is_nil(err)
        end)

        local t2 = ngx.thread.spawn(function()
          local _, err = db:cluster_mutex("my_key_3", nil, cb2)
          assert.is_nil(err)
        end)

        ngx.thread.wait(t1)
        ngx.thread.wait(t2)

        assert.spy(cb1).was_called()
        assert.spy(cb2).was_called()
      end)


      it("mutex cannot be held for longer than opts.ttl across nodes (DB lock)", function()
        local cb1 = spy.new(function()
          -- remove worker lock
          ngx.shared.kong_locks:delete("my_key_5")
          -- make DB lock expire
          ngx.sleep(1)
        end)

        local cb2 = spy.new(function() end)

        local t1 = ngx.thread.spawn(function()
          local ok, err = db:cluster_mutex("my_key_5", { ttl = 0.5 }, cb1)
          assert.is_nil(err)
          assert.equal(true, ok)
        end)

        local t2 = ngx.thread.spawn(function()
          local ok, err = db:cluster_mutex("my_key_5", { ttl = 0.5 }, cb2)
          assert.is_nil(ok)
          assert.matches("%[%w+ error%] timeout", err)
        end)

        ngx.thread.wait(t1)
        ngx.thread.wait(t2)

        assert.spy(cb1).was_called()
        assert.spy(cb2).was_not_called()
      end)
    end)
  end)
end
