local looper = require "kong.portal.render_toolset.looper"

describe("base helpers", function()
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe("looper", function()
    it("can index strings in nested table", function()
      local object = {}
      looper.set_node(object)

      object.a = { b = "c" }

      assert.equals(object.a.b, "c")
      assert.is_nil(object.b)
      assert.is_nil(object.b.c.d)
    end)

    it("can index numbers in nested table", function()
      local object = {}
      looper.set_node(object)

      object.a = { b = 0 }

      assert.equals(object.a.b, 0)
      assert.is_nil(object.a.b.c.d)
      assert.is_nil(object.b.c.d)
    end)

    it("can index strings in nested table added when items added after instantiation", function()
      local object = {}
      looper.set_node(object)
      object.a = { b = "c" }

      assert.equals(object.a.b, "c")
      assert.is_nil(object.b)
      assert.is_nil(object.b.c.d)
    end)

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
      assert.is_nil(object.c.d.e.f)
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
      assert.is_nil(object.b("dog").a)
      assert.is_nil(object.b("dog").a.b.c)
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
      assert.is_nil(object.a.b.c, nil)

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
  end)
end)
