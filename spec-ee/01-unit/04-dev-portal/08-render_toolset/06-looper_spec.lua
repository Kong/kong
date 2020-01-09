local looper = require "kong.portal.render_toolset.looper"

-- XXX: looper.set_node patches `nil` making any test that runs after this one
-- use the patched entity instead of the real one, even when busted is
-- insulating every describe block
pending("base helpers", function()
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe("looper", function()
    it("can index functions that take no arg", function()
      local object = {}
      looper.set_node(object)
      local get = function()
        return "dog"
      end

      object.b = get
      object.c = { d = get }

      assert.equals(object.b, "dog")
      assert.equals(object.b, "dog")
      assert.equals(object.c.d, "dog")
    end)

    it("can call functions that take args", function()
      local object = {}
      looper.set_node(object)
      local get = function(arg)
        return arg
      end

      object.b = get
      object.c = { d = get }

      assert.is_nil(object.b.c)
      assert.equals(object.b("dog"), "dog")
      assert.equals(object.c.d("dog"), "dog")
    end)

    it("can deal with mixed tables", function()
      local object = {
        a = "x",
        b = function()
          return "y"
        end,
        c = function(arg)
          return arg
        end,
        d = {
          e = "l",
          f = function()
            return "m"
          end
        },
      }

      looper.set_node(object)
      object.bool = function()
        return false
      end

      assert.equals(object.a, "x")
      assert.equals(object.b(), "y")
      assert.is_nil(object.b().a, nil)
      assert.is_nil(object.b.a, nil)

      assert.equals(object.c("dog"), "dog")
      assert.is_nil(object.c("dog").d, "dog")
      assert.is_nil(object.c.e)

      assert.equals(object.bool, false)

      assert.equals(object.d.e, "l")
      assert.equals(object.d.f(), "m")
      assert.is_nil(object.d.e.a)
      assert.is_nil(object.d.f().a)
    end)

    it("does not override global types", function()
      local object = {}
      looper.set_node(object)
      local get = function()
        return "x"
      end

      object.a = get
      object.b = "x"
      object.c = 1
      object.d = true
      object.e = nil

      assert.equals(object.a, "x")
      assert.equals(type(object.a), "string")
      local ok, _ = pcall(function() return object.b.c.d end)
      assert.falsy(ok)
      local ok, _ = pcall(function() return object.c.c.d end)
      assert.falsy(ok)
      local ok, _ = pcall(function() return object.d.c.d end)
      assert.falsy(ok)
      local ok, _ = pcall(function() return object.e.c.d end)
      assert.falsy(ok)

      local object_b = {}
      local get = function()
        return "x"
      end

      object_b.a = get
      object_b.b = "x"
      object_b.c = 1
      object_b.d = true
      object_b.e = nil

      assert.equals(type(object_b.a), "function")
      local ok, _ = pcall(function() return object_b.b.c.d end)
      assert.falsy(ok)
      local ok, _ = pcall(function() return object_b.c.c.d end)
      assert.falsy(ok)
      local ok, _ = pcall(function() return object_b.d.c.d end)
      assert.falsy(ok)
      local ok, _ = pcall(function() return object_b.e.c.d end)
      assert.falsy(ok)
    end)
  end)
end)
