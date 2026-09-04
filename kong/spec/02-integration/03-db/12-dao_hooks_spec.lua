local helpers = require "spec.helpers"
local hooks = require "kong.hooks"


for _, strategy in helpers.each_strategy() do
  describe("kong.db hooks [#" .. strategy .. "]", function()
    local db, bp, s1, r1

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      })

      s1 = bp.services:insert {
        name = "s1",
        url = "http://example.test",
      }

      r1 = bp.routes:insert {
        protocols = { "http" },
        hosts = { "host1" },
        service = s1,
        name = "r1",
      }
    end)

    describe("page_for", function()
      local pre_hook = spy.new(function() end)
      local post_hook = spy.new(function() end)

      lazy_setup(function()
        hooks.register_hook("dao:page_for:pre", function()
          pre_hook()
          return true
        end)
        hooks.register_hook("dao:page_for:post", function()
          post_hook()
          return true
        end)
      end)

      it("calls hooks", function()
        finally(function()
          hooks.clear_hooks()
        end)

        assert(db.routes:page_for_service(s1))
        assert.spy(pre_hook).was_called(1)
        assert.spy(post_hook).was_called(1)
      end)
    end)

    describe("select_by", function()
      local pre_hook = spy.new(function() end)
      local post_hook = spy.new(function() end)

      lazy_setup(function()
        hooks.register_hook("dao:select_by:pre", function()
          pre_hook()
          return true
        end)
        hooks.register_hook("dao:select_by:post", function()
          post_hook()
          return true
        end)
      end)

      it("calls hooks", function()
        finally(function()
          hooks.clear_hooks()
        end)

        assert(db.routes:select_by_name("r1"))
        assert.spy(pre_hook).was_called(1)
        assert.spy(post_hook).was_called(1)
      end)
    end)

    describe("update_by", function()
      local pre_hook = spy.new(function() end)
      local post_hook = spy.new(function() end)

      lazy_setup(function()
        hooks.register_hook("dao:update_by:pre", function()
          pre_hook()
          return true
        end)
        hooks.register_hook("dao:update_by:post", function()
          post_hook()
          return true
        end)
      end)

      it("calls hooks", function()
        finally(function()
          hooks.clear_hooks()
        end)

        assert(db.routes:update_by_name("r1", {
          protocols = { "http", "https" } }
        ))
        assert.spy(pre_hook).was_called(1)
        assert.spy(post_hook).was_called(1)
      end)
    end)

    describe("upsert_by", function()
      local pre_hook = spy.new(function() end)
      local post_hook = spy.new(function() end)

      lazy_setup(function()
        hooks.register_hook("dao:upsert_by:pre", function()
          pre_hook()
          return true
        end)
        hooks.register_hook("dao:upsert_by:post", function()
          post_hook()
          return true
        end)
      end)

      it("calls hooks", function()
        finally(function()
          hooks.clear_hooks()
        end)

        assert(db.routes:upsert_by_name("r3",
          {
            protocols = { "http", "https" },
            service = s1,
            hosts = { "host1" },
          }
        ))
        assert.spy(pre_hook).was_called(1)
        assert.spy(post_hook).was_called(1)
      end)
    end)

    describe("delete_by", function()
      local pre_hook = spy.new(function() end)
      local post_hook = spy.new(function() end)

      lazy_setup(function()
        hooks.register_hook("dao:delete_by:pre", function()
          pre_hook()
          return true
        end)
        hooks.register_hook("dao:delete_by:post", function()
          post_hook()
          return true
        end)
      end)

      it("calls hooks", function()
        finally(function()
          hooks.clear_hooks()
        end)

        assert(db.routes:delete_by_name("r3"))
        assert.spy(pre_hook).was_called(1)
        assert.spy(post_hook).was_called(1)
      end)
    end)

    describe("select", function()
      local pre_hook = spy.new(function() end)
      local post_hook = spy.new(function() end)

      lazy_setup(function()
        hooks.register_hook("dao:select:pre", function()
          pre_hook()
          return true
        end)
        hooks.register_hook("dao:select:post", function()
          post_hook()
          return true
        end)
      end)

      it("calls hooks", function()
        finally(function()
          hooks.clear_hooks()
        end)

        assert(db.routes:select(r1))
        assert.spy(pre_hook).was_called(1)
        assert.spy(post_hook).was_called(1)
      end)
    end)

    describe("page", function()
      local pre_hook = spy.new(function() end)
      local post_hook = spy.new(function() end)

      lazy_setup(function()
        hooks.register_hook("dao:page:pre", function()
          pre_hook()
          return true
        end)
        hooks.register_hook("dao:page:post", function()
          post_hook()
          return true
        end)
      end)

      it("calls hooks", function()
        finally(function()
          hooks.clear_hooks()
        end)

        assert(db.routes:page())
        assert.spy(pre_hook).was_called(1)
        assert.spy(post_hook).was_called(1)
      end)
    end)

    describe("insert", function()
      local pre_hook = spy.new(function() end)
      local post_hook = spy.new(function() end)

      lazy_setup(function()
        hooks.register_hook("dao:insert:pre", function()
          pre_hook()
          return true
        end)
        hooks.register_hook("dao:insert:post", function()
          post_hook()
          return true
        end)
      end)

      it("calls hooks", function()
        finally(function()
          hooks.clear_hooks()
        end)

        assert(db.routes:insert({
          protocols = { "http" },
          hosts = { "host1" },
          service = s1,
          name = "r5",
        }))
        assert.spy(pre_hook).was_called(1)
        assert.spy(post_hook).was_called(1)
      end)
    end)

    describe("update", function()
      local pre_hook = spy.new(function() end)
      local post_hook = spy.new(function() end)

      lazy_setup(function()
        hooks.register_hook("dao:update:pre", function()
          pre_hook()
          return true
        end)
        hooks.register_hook("dao:update:post", function()
          post_hook()
          return true
        end)
      end)

      it("calls hooks", function()
        finally(function()
          hooks.clear_hooks()
        end)

        assert(db.routes:update(r1, {
          protocols = { "http" },
          hosts = { "host1" },
          service = s1,
          name = "r10",
        }))
        assert.spy(pre_hook).was_called(1)
        assert.spy(post_hook).was_called(1)
      end)
    end)
  end)
end
