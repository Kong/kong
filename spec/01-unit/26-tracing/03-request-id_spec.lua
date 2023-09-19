local request_id = require "kong.tracing.request_id"
local utils = require "kong.tools.utils"

local to_hex = require "resty.string".to_hex
local size = require "pl.tablex".size

local rand_bytes = utils.get_rand_bytes

local function new_id()
  return to_hex(rand_bytes(16))
end

local function reset_context(id)
  _G.ngx = {
    ctx = {},
    var = {
      kong_request_id = id,
    },
    get_phase = function()
      return "access"
    end,
  }
  _G.kong = {
    log = {
      notice = function() end,
      info = function() end,
    },
  }
end


describe("Request ID unit tests", function()
  local kong_request_id_value = "1234"
  local types = {}

  lazy_setup(function()
    -- prepare a sorted list of the request id types to facilitate
    -- iterations later
    for _, type in pairs(request_id.TYPES) do
      types[#types+1] = type
    end
    table.sort(types, function(t1, t2)
      return t1.priority < t2.priority
    end)
  end)

  before_each(function()
    reset_context(kong_request_id_value)
  end)

  describe("get()", function()
    it("initializes the Request ID with type INIT and returns it correctly", function()
      local request_id_value, err = request_id.get()
      assert.is_nil(err)
      assert.equal(kong_request_id_value, request_id_value)

      local ctx_request_id = request_id._get_ctx_request_id()
      assert.not_nil(ctx_request_id)
      assert.same(request_id.TYPES.INIT, ctx_request_id.type)
    end)
  end)

  describe("set()", function()
    local spy_kong_log_notice

    before_each(function()
      reset_context(kong_request_id_value)
    end)

    it("fails if called from an unexpected phase", function()
      local invalid_phase = "init_worker"
      _G.ngx.get_phase = function()
        return invalid_phase
      end

      local _, err = request_id.set( "abcd", request_id.TYPES.INIT)
      assert.matches("cannot set request_id in '" .. invalid_phase .. "' phase", err)
    end)

    it("fails if called without the required parameters", function()
      local ok, err = request_id.set("abcd")

      assert.is_nil(ok)
      assert.equals("both id and type are required", err)

      ok, err = request_id.set(nil, request_id.TYPES.INIT)

      assert.is_nil(ok)
      assert.equals("both id and type are required", err)
    end)

    it("sets the Request ID with the provided type and logs the expected message", function()
      for _, type in ipairs(types) do
        reset_context(kong_request_id_value)
        -- need to set the spy after resettig the context
        spy_kong_log_notice = spy.on(kong.log, "notice")

        local request_id_value = new_id()
        request_id.set(request_id_value, type)

        local v, err = request_id.get()
        assert.is_nil(err)
        assert.equal(request_id_value, v)

        local ctx_request_id = request_id._get_ctx_request_id()
        assert.not_nil(ctx_request_id)
        assert.same(type, ctx_request_id.type)

        assert.spy(spy_kong_log_notice).was_called_with(
            "setting request_id to: '", request_id_value, "' (", type.name, ") for the current request")
      end
    end)

    it("sets the Request ID when it has higher priority than the current", function()
      for i = 1, size(types) do
        reset_context(kong_request_id_value)

        -- manually set old type
        local old_type = types[i]
        request_id._set_ctx_request_id("abc", old_type)

        local request_id_value = new_id()
        -- types are sorted by priority (lower value == lower priority)
        -- previous types (less prioritary) should fail the priority check
        for j = 1, i - 1 do
          local new_type = types[j]
          local ok, err = request_id.set(request_id_value, new_type)
          assert.is_nil(ok)
          assert.equal("priority check failed for request_id: " .. request_id_value .. " (" .. new_type.name .. ")", err)
        end

        -- next types (more prioritary) should pass the priority check
        for j = i, size(types) do
          local new_type = types[j]
          local _, err = request_id.set(request_id_value, new_type)
          assert.is_nil(err)
        end
      end
    end)
  end)

  describe("should_overwrite_id()", function()
    it("returns true when the new type has higher priority than the old one, false otherwise", function()
      local spy_kong_log_info = spy.on(kong.log, "info")

      for i = 1, size(types) do
        local old_type = types[i]

        -- previous types (less prioritary) should not overwrite the current one
        for j = 1, i - 1 do
          local new_type = types[j]
          assert.is_false(request_id._should_overwrite_id(new_type, old_type))
          assert.spy(spy_kong_log_info).was_called_with("request_id of type: ", new_type.name,
                                                        "is less prioritary than current type: ", old_type.name)
        end

        spy_kong_log_info:clear()
        -- next types (more prioritary) should overwrite the current one
        for j = i, size(types) do
          local new_type = types[j]
          assert.is_true(request_id._should_overwrite_id(new_type, old_type))
          assert.spy(spy_kong_log_info).was_not_called()
        end
      end
    end)
  end)
end)
