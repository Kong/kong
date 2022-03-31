-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local tx = require "pl.tablex"

local license_helpers = require "kong.enterprise_edition.license_helpers"

local tx_deepcopy = tx.deepcopy
local tx_deepcompare = tx.deepcompare

local _M = {}

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


local MagicTable = function(uberself, lazy, evaluator)

  local source

  if lazy then
    source = {}
  end

  local evaluator = evaluator or function(self, value)
    return value(self)
  end

  local methods = {
    clear = table.clear,
    update = function(self, data, eval)

      -- update source when lazy
      if lazy then
        source = data

        return
      end

      -- [...] this does the same as pl.tablex.update
      for k, v in pairs(data) do

        if eval and type(v) == "function" then
          v = evaluator(self, v)
        end

        rawset(self, k, v)
      end
    end,
  }

  local index = function(self, key)

    if methods[key] then
      return methods[key]
    end

    local value

    if lazy then
      value = source[key]

      if type(value) == "function" then
        value = evaluator(self, value)
      end

      rawset(self, key, value)
    else
      value = rawget(self, key)
    end

    return value
  end

  return setmetatable(uberself, {
    __index = index,
    __newindex = function() error("cannot write to MagicTable™", 2) end,
  })
end


_M.MagicTable = MagicTable

-- Lazy magic table
_M.features = MagicTable({}, true)
-- Non lazy magic table
_M.configuration = MagicTable({}, false)


function _M:register_events(events_handler)

  -- declarative conf changed (CP update) -- received by all workers
  events_handler.register(function(data, event, source, pid)
    local license = license_helpers.read_license_info()

    -- nothing changed
    if kong and kong.license and tx_deepcompare(kong.license, license) then
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
    if kong and kong.license and tx_deepcompare(kong.license, license) then
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

  _M.features:clear()
  _M.features:update(tx_deepcopy(license_helpers.get_featureset(_M.l_type)))

  _M.configuration:clear()
  _M.configuration:update(tx_deepcopy(_M.kong_conf))
  _M.configuration:update(_M.features.conf or {}, true)

  ngx.log(ngx.DEBUG, "[licensing] license type: ", _M.l_type)
end


-- boolean shortcut
-- licensing:can("ee_plugins") always true | false
function _M:can(what)
  return _M.features[what] ~= false
end


function _M:new(kong_conf)
  local license = license_helpers.read_license_info()

  _M.kong_conf = kong_conf
  _M:update(license)

  return _M
end


return setmetatable(_M, { __call = _M.new, __index = _M.features })
