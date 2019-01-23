local mocker = {}

-- Setup mocks, which are undone in a finally() block
-- @param finally The `finally` function, that needs to be passed in because
-- Busted generates it dynamically.
-- @param args A table containing three optional fields:
-- * modules: an array of pairs (module name, module content).
--   This allows modules to be declared in order.
-- * kong: a mock of the kong global (which will fallback to the default one
--   via metatable)
-- * ngx: a mock of the ngx global (which will fallback to the default one
--   via metatable)
function mocker.setup(finally, args)

  local mocked_modules = {}
  local _ngx = _G.ngx
  local _kong = _G.kong

  local function mock_module(name, tbl)
    local old_module = require(name)
    mocked_modules[name] = true
    package.loaded[name] = setmetatable(tbl or {}, {
      __index = old_module,
    })
  end

  if args.ngx then
    _G.ngx = setmetatable(args.ngx, { __index = _ngx })
  end

  if args.kong then
    _G.kong = setmetatable(args.kong, { __index = _kong })
  end

  if args.modules then
    for _, pair in ipairs(args.modules) do
      mock_module(pair[1], pair[2])
    end
  end

  finally(function()
    _G.ngx = _ngx
    _G.kong = _kong

    for k in pairs(mocked_modules) do
      package.loaded[k] = nil
    end
  end)
end


function mocker.table_where_every_key_returns(value)
  return setmetatable({}, {
     __index = function()
                 return value
               end
  })
end


return mocker
