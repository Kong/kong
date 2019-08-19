local getters = require "kong.portal.render_toolset.getters"
local handler    = require "kong.portal.render_toolset.handler"


describe("user", function()
  local user
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
  end)

  after_each(function()
    snapshot:revert()
  end)

  before_each(function()
    stub(getters, "select_authenticated_developer").returns({
        consumer = {
            id = "9b1a577a-9fa6-4ea6-9a29-110401128398"
        },
        created_at = 1562866172,
        email = "j@konghq.com",
        id = "eb40f195-e580-48c9-9a57-049d71515b41",
        meta = "{\"full_name\": \"jordan\"}",
        status = 0,
        updated_at = 1562866172
    })
  end)

  describe("info", function()
    before_each(function()
      user = handler.new("user")
    end)

    it("can fetch user", function()
      local res = user():info()()

      assert.equals("j@konghq.com", res["email"])
      assert.equals("eb40f195-e580-48c9-9a57-049d71515b41", res["id"])
      assert.equals(1562866172, res["created_at"])
    end)
  end)

  describe("is_authenticated", function()
    before_each(function()
      user = handler.new("user")
    end)

    it("can fetch user", function()
      local res = user():is_authenticated()()

      assert.equals('true', tostring(res))
    end)
  end)
end)
