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
        local ok1, err1, ok2, err2
        local t1 = ngx.thread.spawn(function()
          ok1, err1 = db:cluster_mutex("my_key", nil, function()
            ngx.sleep(0.1)
          end)
        end)

        local t2 = ngx.thread.spawn(function()
          ok2, err2 = db:cluster_mutex("my_key", nil, function() end)
        end)

        ngx.thread.wait(t1)
        ngx.thread.wait(t2)

        assert.is_nil(err1)
        assert.equal(true, ok1)
        assert.is_nil(err2)
        assert.equal(false, ok2)
      end)


      it("mutex ensures only one callback gets called", function()
        local cb1 = spy.new(function() end)
        local cb2 = spy.new(function() ngx.sleep(0.3) end)
        local err1, err2

        local t1 = ngx.thread.spawn(function()
          ngx.sleep(0.2)

          _, err1 = db:cluster_mutex("my_key_2", { owner = "1" }, cb1)
        end)

        local t2 = ngx.thread.spawn(function()
          _, err2 = db:cluster_mutex("my_key_2", { owner = "2" }, cb2)
        end)

        ngx.thread.wait(t1)
        ngx.thread.wait(t2)

        assert.is_nil(err1)
        assert.is_nil(err2)
        assert.spy(cb2).was_called()
        assert.spy(cb1).was_not_called()
      end)


      it("mutex can be subsequently acquired once released", function()
        local cb1 = spy.new(function() end)
        local cb2 = spy.new(function() end)
        local err1, err2

        local t1 = ngx.thread.spawn(function()
          _, err1 = db:cluster_mutex("my_key_3", nil, cb1)
        end)

        -- to make sure `db:cluster_mutex` is called subsequently.
        -- even if we didn't call ngx.sleep() explicitly, it will
        -- yield in `db:cluster_mutex`
        ngx.thread.wait(t1)

        local t2 = ngx.thread.spawn(function()
          _, err2 = db:cluster_mutex("my_key_3", nil, cb2)
        end)

        ngx.thread.wait(t2)

        assert.is_nil(err1)
        assert.is_nil(err2)
        assert.spy(cb1).was_called()
        assert.spy(cb2).was_called()
      end)


      it("mutex cannot be held for longer than opts.ttl across nodes (DB lock)", function()
        local ok1, err1, ok2, err2
        local cb1 = spy.new(function()
          -- make DB lock expire
          ngx.sleep(1)
        end)

        local cb2 = spy.new(function() end)

        local t1 = ngx.thread.spawn(function()
          ok1, err1 = db:cluster_mutex("my_key_5", { ttl = 0.5 }, cb1)
        end)

        -- remove worker lock
        ngx.shared.kong_locks:delete("my_key_5")

        local t2 = ngx.thread.spawn(function()
          ok2, err2 = db:cluster_mutex("my_key_5", { ttl = 0.5 }, cb2)
        end)

        ngx.thread.wait(t1)
        ngx.thread.wait(t2)

        assert.is_nil(err1)
        assert.equal(true, ok1)
        assert.is_nil(ok2)
        assert.matches("%[%w+ error%] timeout", err2)
        assert.spy(cb1).was_called()
        assert.spy(cb2).was_not_called()
      end)
    end)
  end)
end
