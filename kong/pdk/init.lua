---
-- The Plugin Development Kit (or "PDK") is set of Lua functions and variables
-- that can be used by plugins to implement their own logic. The PDK is a
-- [Semantically Versioned](https://semver.org/) component, originally
-- released in Kong 0.14.0. The PDK will be guaranteed to be forward-compatible
-- from its 1.0.0 release and on.
--
-- As of this release, the PDK has not yet reached 1.0.0, but plugin authors
-- can already depend on it for a safe and reliable way of interacting with the
-- request, response, or the core components.
--
-- The Plugin Development Kit is accessible from the `kong` global variable,
-- and various functionalities are namespaced under this table, such as
-- `kong.request`, `kong.log`, etc...
--
-- @module PDK
-- @release 1.0.0


---
-- Top-level variables
-- @section top_level_variables


---
-- A human-readable string containing the version number of the currently
-- running node.
--
-- @field kong.version
-- @usage print(kong.version) -- "2.0.0"


---
-- An integral number representing the version number of the currently running
-- node, useful for comparison and feature-existence checks.
--
-- @field kong.version_num
-- @usage
-- if kong.version_num < 13000 then -- 000.130.00 -> 0.13.0
--   -- no support for Routes & Services
-- end


---
-- A number representing the major version of the current PDK (e.g.
-- `1`). Useful for feature-existence checks or backwards-compatible behavior
-- as users of the PDK.
--
-- @field kong.pdk_major_version
-- @usage
-- if kong.pdk_version_num < 2 then
--   -- PDK is below version 2
-- end


---
-- A human-readable string containing the version number of the current PDK.
--
-- @field kong.pdk_version
-- @usage print(kong.pdk_version) -- "1.0.0"


---
-- A read-only table containing the configuration of the current Kong node,
-- based on the configuration file and environment variables.
--
-- See [kong.conf.default](https://github.com/Kong/kong/blob/master/kong.conf.default)
-- for details.
--
-- Comma-separated lists in that file get promoted to arrays of strings in this
-- table.
--
-- @field kong.configuration
-- @usage
-- print(kong.configuration.prefix) -- "/usr/local/kong"
-- -- this table is read-only; the following throws an error:
-- kong.configuration.prefix = "foo"


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


--- Router module
-- @field kong.router
-- @redirect kong.router


--- Nginx module
-- @field kong.nginx
-- @redirect kong.nginx


--- Singletons
-- @section singletons


---
-- Instance of Kong's DAO (the `kong.db` module). Contains accessor objects
-- to various entities.
--
-- A more thorough documentation of this DAO and new schema definitions is to
-- be made available in the future.
--
-- @field kong.db
-- @usage
-- kong.db.services:insert()
-- kong.db.routes:select()


---
-- Instance of Kong's DNS resolver, a client object from the
-- [lua-resty-dns-client](https://github.com/kong/lua-resty-dns-client) module.
--
-- **Note:** usage of this module is currently reserved to the core or to
-- advanced users.
--
-- @field kong.dns


---
-- Instance of Kong's IPC module for inter-workers communication from the
-- [lua-resty-worker-events](https://github.com/Kong/lua-resty-worker-events)
-- module.
--
-- **Note:** usage of this module is currently reserved to the core or to
-- advanced users.
--
-- @field kong.worker_events


---
-- Instance of Kong's cluster events module for inter-nodes communication.
--
-- **Note:** usage of this module is currently reserved to the core or to
-- advanced users.
--
-- @field kong.cluster_events


---
-- Instance of Kong's database caching object, from the `kong.cache` module.
--
-- **Note:** usage of this module is currently reserved to the core or to
-- advanced users.
--
-- @field kong.cache

---
-- Instance of Kong's IP module to determine whether a given IP address is
-- trusted
-- @field kong.ip
-- @redirect kong.ip

--- Utilities
-- @section utilities


--- Node-level utilities
-- @field kong.node
-- @redirect kong.node


--- Utilities for Lua tables
-- @field kong.table
-- @redirect kong.table


--- Instance of Kong logging factory with various utilities
-- @field kong.log
-- @redirect kong.log


assert(package.loaded["resty.core"])


local MAJOR_VERSIONS = {
  [1] = {
    version = "1.3.0",
    modules = {
      "table",
      "node",
      "log",
      "ctx",
      "ip",
      "client",
      "service",
      "request",
      "service.request",
      "service.response",
      "response",
      "router",
      "nginx",
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
