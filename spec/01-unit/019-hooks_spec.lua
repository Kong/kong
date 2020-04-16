local hooks = require "kong.hooks"

local c = 0
local function s()
  c=c+1
  return tostring(c)
end


describe("hooks", function()
  local h
  before_each(function()
    h = s()
  end)

  it("runs a non-initialized hook and doesn't err", function()
    hooks.run_hook(h)
    assert(true)
  end)

  it("wraps 1 function by default", function()
    hooks.register_hook(h, function() return 1 end)
    assert.equal(1, hooks.run_hook(h))
  end)

  it("wraps 2 functions by default", function()
    hooks.register_hook(h, function() return 1 end)
    hooks.register_hook(h, function() return 1 end)
    assert.equal(1, hooks.run_hook(h))
  end)

  it("by default first that returns nil/false cuts the flow", function()
    hooks.register_hook(h, function() return nil end)
    hooks.register_hook(h, function() return 1 end)
    assert.is_nil(hooks.run_hook(h))
  end)

  it("errors when passing a non-function parameter to a hook", function()
    assert.is_falsy(pcall(function() hooks.register_hook(h) end))
  end)

  it("works with multiple return values", function()
    hooks.register_hook(h, function() return 1,2 end)
    assert.same({1,2}, {hooks.run_hook(h)})
  end)

  it("calls multiple functions", function()
    local count = 0
    local f = function()
      count = count+1
      return true
    end

    hooks.register_hook(h, f)
    hooks.register_hook(h, f)

    hooks.register_hook(h, function() return 1 end)

    assert.equal(1, hooks.run_hook(h))
    assert.equal(2, count)
  end)

  it("calls with parameters", function()
    local count = 0
    local f = function(a, b)
      return {a,b}
    end

    hooks.register_hook(h, f)
    hooks.register_hook(h, f)
    local r = hooks.run_hook(h, 1, 2)

    assert.equal(1, r[1])
    assert.equal(2, r[2])
  end)

  it("can run raw functions", function()
    local function f(acc, i)
      acc = acc or {}
      table.insert(acc, acc and acc[#acc] and acc[#acc]+1 or 0)
      return acc
    end
    hooks.register_hook(h, f, {raw=true})
    hooks.register_hook(h, f, {raw=true})
    hooks.register_hook(h, f, {raw=true})

    assert.same({0,1,2}, {hooks.run_hook(h, 0)})
  end)
end)
