-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}

local tablex = require "pl.tablex"

local license_helpers = require "kong.enterprise_edition.license_helpers"

local compare = tablex.deepcompare

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

local _features = {}

_M.features = setmetatable({}, {
  __index = function(self, key)

    local methods = {
      clear = table.clear,
      update = function(self, data)
        self:clear()
        _features = data
      end,
    }

    if methods[key] then
      return methods[key]
    end

    local value = _features[key]

    if type(value) == "function" then
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

    local methods = {
      clear = table.clear,
    }

    if methods[key] then
      return methods[key]
    end

    local value = _M.features.conf[key]

    if value == nil then
      value = _M.kong_conf[key]
    end

    rawset(self, key, value)

    return value
  end,
  __newindex = function()
    error("cannot write to configuration", 2)
  end,
})


function _M:register_events(events_handler)

  -- declarative conf changed (CP update) -- received by all workers
  events_handler.register(function(data, event, source, pid)
    local license = license_helpers.read_license_info()

    -- nothing changed
    if kong and kong.license and compare(kong.license, license) then
      ngx.log(ngx.DEBUG, "[licensing] license has not changed")
      return
    end

    -- propagate it to self
    events_handler.post_local("license", "load", { license = license })

  end, "declarative", "flip_config")

  -- db license changed event -- received on one worker
  events_handler.register(function(data, event, source, pid)
    local license = license_helpers.read_license_info()

    -- nothing changed
    if kong and kong.license and compare(kong.license, license) then
      ngx.log(ngx.DEBUG, "[licensing] license has not changed")
      return
    end

    -- propagate it to all workers
    ngx.log(ngx.DEBUG, "[licensing] broadcasting license reload event to all workers. license: ", tostring(license ~= nil))
    events_handler.post("license", "load", { license = license })

  end, "crud", "licenses")

  -- XXX does master process receive this event? does it mattress?
  events_handler.register(function(data, event, source, pid)
    ngx.log(ngx.DEBUG, "[licensing] license:load event -> license: ", tostring(data.license ~= nil))

    local _l_type = _M.l_type

    _M:update(data.license)

    -- nothing changed
    if _l_type == _M.l_type then
      ngx.log(ngx.DEBUG, "[licensing] license type has not changed")
      return
    end

    events_handler.post_local("kong:configuration", "change", {
      configuration = _M.configuration,
      features = _M.features,
      l_type = _M.l_type,
    })

  end, "license", "load")

end


function _M:init_worker(events_handler)
  license_helpers.report_expired_license()
  self:register_events(events_handler)
end


function _M:update(license)
  -- set kong license
  if kong then
    kong.license = license
  end

  _M.l_type = license_helpers.get_type(license)
  _M.features:update(license_helpers.get_featureset(_M.l_type))
  _M.configuration:clear()

  ngx.log(ngx.DEBUG, "[licensing] license type: ", _M.l_type)
end


-- boolean shortcut
-- licensing:can("ee_plugins") always true | false
function _M:can(what)
  return not (_M.features[what] == false)
end


function _M:new(kong_conf)
  local license = license_helpers.read_license_info()

  _M.kong_conf = kong_conf
  _M:update(license)

  return _M
end


return setmetatable(_M, { __call = _M.new, __index = _M.features })
