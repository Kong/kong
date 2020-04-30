local hooks = require "kong.hooks"


describe("hooks", function()
  local c = 0
  local function s()
    c=c+1
    return tostring(c)
  end

  local h
  before_each(function()
    h = s()
  end)

  it("runs a non-initialized hook and doesn't err", function()
    assert.not_error(function() hooks.run_hook(h) end)
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
    local f = function(a, b)
      return {a,b}
    end

    hooks.register_hook(h, f)
    hooks.register_hook(h, f)
    local r = hooks.run_hook(h, 1, 2)

    assert.same({1, 2}, r)
  end)

  it("can run low-level functions", function()
    local function f(acc, i)
      acc = acc or {}
      table.insert(acc, acc[#acc] and acc[#acc]+1 or 0)
      return acc
    end
    hooks.register_hook(h, f, {low_level=true})
    hooks.register_hook(h, f, {low_level=true})
    hooks.register_hook(h, f, {low_level=true})

    assert.same({0,1,2}, {hooks.run_hook(h, 0)})
  end)
end)
