---
-- Kong's "Plugin Development Kit" ("PDK")
--
-- @module kong
-- @release 0.1.1 (RFC)

--- Top-level variables
-- @section top_level_variables

---
-- A human-readable string containing the version number of the currently running node.
-- @field kong.version
-- @usage
-- print(kong.version) -- "0.13.0"

---
-- An integral number representing the version number of the currently running
-- node, useful for comparison and feature-existence checks.
-- @field kong.version_num
-- @usage
-- if kong.version_num < 13000 then -- 000.130.00 -> 0.13.0
-- -- no support for Routes & Services
-- end

---
-- A number representing the major version of the current PDK (e.g.
-- `1`). Useful for feature-existence checks or backwards-compatible behavior as
-- users of the PDK.
-- @field kong.pdk_major_version
-- @usage
-- if kong.pdk_version_num < 2 then
-- -- PDK is below version 2
-- end

---
-- A human-readable string containing the version number of the current PDK.
-- @field kong.pdk_version
-- @usage print(kong.pdk_version) -- "1.0.0"

---
-- A read-only table containing the configuration of the current Kong node, based
-- on the configuration file and environment variables.
--
-- See [kong.conf.default](https://github.com/Kong/kong/blob/master/kong.conf.default) for details.
-- Comma-separated lists in that file get promoted to arrays of strings in this
-- table.th
-- @field kong.configuration
-- @usage
-- print(kong.configuration.prefix) -- "/usr/local/kong"
-- -- read-only, throws an error:
-- kong.configuration.custom_plugins = "foo"

--- 1st class utilities
-- @section first_class_utilities

---
-- Instance of Kong's legacy DAO. This has the same interface as the object
-- returned by `new(config, db)` in core's `kong.dao.factory` module.
--
-- > **Rationale:** given this is the legacy DAO, we don't expect further
-- > development or improvements on this interface.
--
-- * getkong.org: [Plugin Development Guide - Accessing the Datastore](https://getkong.org/docs/latest/plugin-development/access-the-datastore/)
-- * Kong legacy DAO: https://github.com/Kong/kong/tree/master/kong/dao
-- @field kong.dao

---
-- Instance of Kong's DAO (the new `kong.db` modules). Contains accessor objects
-- to various entities.
-- A more thorough documentation of this DAO and new schema definitions is to be
-- made available in the future, once this object will replace the old DAO as the
-- standard interface with which to create custom entities in plugins.
-- @field kong.db
-- @usage
-- kong.db.services:insert()
-- kong.db.routes:select()

---
-- Instance of Kong's DNS resolver, a client object from the
-- [lua-resty-dns-client](https://github.com/kong/lua-resty-dns-client) module.
--
-- **Note:** usage of this module is currently reserved to the core or to advanced users.
-- @field kong.dns

---
-- Instance of Kong's IPC module for inter-workers communication from the
-- [lua-resty-worker-events](https://github.com/Kong/lua-resty-worker-events)
-- module.
--
-- **Note:** usage of this module is currently reserved to the core or to advanced users.
-- @field kong.ipc

---
-- Instance of Kong's database caching object, from the `kong.cache` module.
--
-- **Note:** usage of this module is currently reserved to the core or to advanced users.
-- @field kong.cache

--- Minor utilities
-- @section minor_utilities

--- Utilities for Lua tables
-- @field kong.table
-- @redirect kong.table

--- Instance of Kong logging factory with various utilities
-- @field kong.log
-- @redirect kong.log

--- Request/Response
-- @section request_response

--- Current request context data
-- @field kong.ctx
-- @redirect kong.ctx

--- Client information module
-- @field kong.client
-- @redirect kong.client

--- Client request module
-- @field kong.request
-- @redirect kong.request

--- Properties of the connection to the Service
-- @field kong.service
-- @redirect kong.service

--- Manipulation of the request to the Service
-- @field kong.service.request
-- @redirect kong.service.request

--- Manipulation of the response from the Service
-- @field kong.service.response
-- @redirect kong.service.response

--- Client response module
-- @field kong.response
-- @redirect kong.response

require("resty.core")


local MAJOR_VERSIONS = {
  [1] = {
    version = "1.0.0",
    modules = {
      "table",
      "log",
      "ctx",
      "ip",
      "client",
      "service",
      "request",
      "service.request",
      "service.response",
      "response",
    },
  },

  latest = 1,
}


local _PDK = {
  major_versions = MAJOR_VERSIONS,
}


function _PDK.new(kong_config, major_version, self)
  if kong_config then
    if type(kong_config) ~= "table" then
      error("kong_config must be a table", 2)
    end

  else
    kong_config = {}
  end

  if major_version then
    if type(major_version) ~= "number" then
      error("major_version must be a number", 2)
    end

  else
    major_version = MAJOR_VERSIONS.latest
  end

  local version_meta = MAJOR_VERSIONS[major_version]

  self = self or {}

  self.pdk_major_version = major_version
  self.pdk_version = version_meta.version

  self.configuration = setmetatable({}, {
    __index = function(_, v)
      return kong_config[v]
    end,

    __newindex = function()
      error("cannot write to configuration", 2)
    end,
  })

  for _, module_name in ipairs(version_meta.modules) do
    local parent = self
    for part in module_name:gmatch("([^.]+)%.") do
      if not parent[part] then
        parent[part] = {}
      end

      parent = parent[part]
    end

    local child = module_name:match("[^.]*$")
    if parent[child] then
      error("PDK module '" .. module_name .. "' conflicts with a key")
    end

    local mod = require("kong.pdk." .. module_name)

    parent[child] = mod.new(self)
  end

  return self
end


return _PDK
