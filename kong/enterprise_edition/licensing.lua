-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local license_helpers = require "kong.enterprise_edition.license_helpers"

-- Provides easy to access License confs and features
--
-- local lic = licensing:new(kong_conf)
--
-- lic.conf          -> LIC_TYPE -> conf
-- lic.configuration -> LIC_TYPE -> conf + kong_conf
-- lic.features      -> LIC_TYPE -> featureset
-- lic.features.foo  -> LIC_TYPE -> featureset -> foo
--
-- lic:can("foo") == (lic.features.foo == true)
--
-- lic:reload()     -> reload LIC_TYPE with current license
--
-- anything in LIC_TYPE -> fetureset can be a function, instead of returning
-- the function, it returns the result of the function (and stores it)


local _M = {}

-- License features
local featureset = {}
local feature_methods = {
  clear = table.clear,
  load = function(self)
    featureset = license_helpers.get_featureset() or {}
  end,
  reload = function(self)
    self:clear()
    self:load()
  end,
}

_M.features = setmetatable({}, {
  __index = function(self, key)

    local value = featureset[key]

    if value == nil then
      return feature_methods[key]
    end

    -- features can be functions that get executed and then stored
    if type(value) == 'function' then
      value = value(_M.configuration)
    end

    rawset(self, key, value)

    return value
  end,
})


-- A configuration table that proxies on the following priority:
--   1. license conf (license conf overrides)
--   2. kong configuration (kong init conf)
-- It can be used as a transparent replacement of kong.configuration
_M.configuration = setmetatable({}, {
  __index = function(self, key)

    local value = _M.features.conf[key]

    if value == nil then
      value = _M.kong_conf[key]
    end

    -- XXX not lazy loaded
    -- it's just a proxy and that's it. Once it works, we do it better
    -- rawset(self, key, value)

    return value
  end,
  __newindex = function()
    error("cannot write to configuration", 2)
  end,
})


function _M:new(kong_conf)
  _M.kong_conf = kong_conf
  _M.features:reload()

  return _M
end


function _M:reload()
  _M.features:reload()
  -- anything else ?
end


-- boolean shortcut
-- licensing:can("ee_plugins") always true | false
function _M:can(what)
  return not (_M.features[what] == false)
end


return setmetatable(_M, { __call = _M.new, __index = _M.features })
