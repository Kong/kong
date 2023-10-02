-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local tx = require "pl.tablex"

local utils = require "kong.tools.utils"
local conf_loader = require "kong.conf_loader"
local license_helpers = require "kong.enterprise_edition.license_helpers"
local event_hooks = require "kong.enterprise_edition.event_hooks"

local tx_deepcompare = tx.deepcompare
local next = next
local string_find = string.find

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

local MagicTable = function(uberself, opts)
  opts = opts or {}

  local source

  if opts.lazy then
    source = {}
  end

  local methods = {
    clear = table.clear,
    update = function(self, data, eval)

      -- update source when lazy
      if opts.lazy then
        source = data

        return
      end

      -- [...] this does the same as pl.tablex.update
      for k, v in pairs(data) do

        if eval and type(v) == "function" then
          v = v(self)
        end

        rawset(self, k, v)
      end
    end,
  }

  if opts.has_remove_sensitive then
    methods.remove_sensitive = function() return conf_loader.remove_sensitive(_M.configuration) end
  end

  local index = function(self, key)

    if methods[key] then
      return methods[key]
    end

    local value

    if opts.lazy then
      value = source[key]

      if type(value) == "function" then
        value = value(self)
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
_M.features = MagicTable({}, { lazy = true })
-- Non lazy magic table
_M.configuration = MagicTable({}, { lazy = false, has_remove_sensitive = true })


-- used for unload license when the license is deployed via Admin API
local FREE_LICENSE = {}

local function get_license_changed()
  local license = license_helpers.read_license_info()

  -- nothing changed
  if kong and kong.license and tx_deepcompare(kong.license, license) then
    ngx.log(ngx.DEBUG, "[licensing] license has not changed")
    return
  end

  return license or FREE_LICENSE
end

local function get_license_event_type(license)
  if not next(license) then
    return "UNLOAD"
  end

  return "LOAD"
end

-- propagate license load event to self worker
local function post_load_license_event_local(worker_events)
  local license = get_license_changed()

  if not license then
    return
  end

  ngx.log(ngx.DEBUG, "[licensing] post license reload event to self worker. license: ", get_license_event_type(license))
  worker_events.post_local("license", "load", { license = license })
end

-- propagate license load event to all workers
local function post_load_license_event(worker_events)
  local license = get_license_changed()

  if not license then
    return
  end

  ngx.log(ngx.DEBUG, "[licensing] broadcasting license reload event to all workers. license: ", get_license_event_type(license))
  worker_events.post("license", "load", { license = license })
end

local function load_license(worker_events, license)
  ngx.log(ngx.DEBUG, "[licensing] license:load event -> license: ", get_license_event_type(license))

  local _l_type = _M.l_type  -- l_type before changed
  _M:update(license)

  -- nothing changed
  if _l_type == _M.l_type then
    ngx.log(ngx.DEBUG, "[licensing] license type has not changed")
    return
  end

  _M:post_conf_change_worker_event()
end

function _M:register_events()
  local kong = kong
  local worker_events = kong.worker_events
  local cluster_events = kong.cluster_events

  -- declarative conf changed (CP update) -- received by all workers
  worker_events.register(function(data, event, source, pid)
    post_load_license_event_local(worker_events)
  end, "declarative", "reconfigure")

  -- db license changed event -- received on one worker
  worker_events.register(function(data, event, source, pid)
    post_load_license_event(worker_events)
  end, "crud", "licenses")

  -- master process would not receive this event, it does't matter
  worker_events.register(function(data, event, source, pid)
    load_license(worker_events, data.license)
  end, "license", "load")

  -- cluster license changed event -- received on one worker per node in a cluster
  -- DP would not received this event
  cluster_events:subscribe("invalidations", function(key)
    if string_find(key, "license") then
      ngx.log(ngx.DEBUG, "[licensing] received invalidate event from cluster ", key)
      post_load_license_event(worker_events)
    end
  end)
end


function _M:init_worker()
  -- XXX reload license after a nginx reload
  local license = license_helpers.read_license_info()
  self:update(license)

  if kong.configuration.role == "data_plane" then
    self:post_conf_change_worker_event()
  end

  license_helpers.report_expired_license(kong.configuration.konnect_mode)
  self:register_events()
end


function _M:post_conf_change_worker_event()
  local worker_events = kong.worker_events
  if not worker_events then
    return  -- dbless init phase, kong.worker_events not needed/available
  end

  -- register event_hooks hooks
  event_hooks.register_events(worker_events)

  worker_events.post_local("kong:configuration", "change", {
    configuration = _M.configuration,
    features = _M.features,
    l_type = _M.l_type,
  })
end


function _M:update(license)
  -- set kong license
  if kong then
    kong.license = license
  end

  _M.l_type = license_helpers.get_type(license)
  ngx.log(ngx.INFO, "[licensing] license type: ", _M.l_type)

  _M.features:clear()
  _M.features:update(utils.cycle_aware_deep_copy(license_helpers.get_featureset(_M.l_type)))

  _M.configuration:clear()
  _M.configuration:update(utils.cycle_aware_deep_copy(_M.kong_conf))
  _M.configuration:update(_M.features.conf or {}, true)
end

function _M:update_featureset()
  local license
  if kong then
    license = kong.license
  end

  if not license then
    return nil
  end

  -- It's already been switched.
  if _M.l_type == license_helpers.get_type(license) then
    return nil
  end

  _M:update(license)
  _M:post_conf_change_worker_event()
end

-- boolean shortcut
-- licensing:can("ee_plugins") always true | false
function _M:can(what)
  return _M.features[what] ~= false
end

function _M:allow_ee_entity(op)
  local allow_ee_entity = _M.features["allow_ee_entity"]

  if not allow_ee_entity then
    return true
  end

  -- should be allowed during the grace period
  if license_helpers.is_exceeds_grace_period() then
    return true
  end

  return allow_ee_entity[op] ~= false
end

function _M:license_type()
  return _M.l_type
end


function _M:new(kong_conf)
  local license = license_helpers.read_license_info()

  _M.kong_conf = kong_conf
  _M:update(license)

  return _M
end


return setmetatable(_M, { __call = _M.new, __index = _M.features })
