-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local setmetatable = setmetatable
local pairs = pairs
local type = type

local function visit(k, n, m, s)
    if m[k] == 0 then return 1 end
    if m[k] == 1 then return end
    m[k] = 0
    local f = n[k]
    for i=1, #f do
        if visit(f[i], n, m, s) then return 1 end
    end
    m[k] = 1
    s[#s+1] = k
end

local tsort = {}
tsort.__index = tsort

function tsort.new()
    return setmetatable({ n = {} }, tsort)
end

function tsort:add(...)
    local p = { ... }
    local c = #p
    if c == 0 then return self end
    if c == 1 then
        p = p[1]
        if type(p) == "table" then
            c = #p
        else
            p = { p }
        end
    end
    local n = self.n
    for i=1, c do
        local f = p[i]
        if n[f] == nil then n[f] = {} end
    end
    for i=2, c, 1 do
        local f = p[i]
        local t = p[i-1]
        local o = n[f]
        o[#o+1] = t
    end
    return self
end

function tsort:sort()
    local n  = self.n
    local s = {}
    local m  = {}
    for k in pairs(n) do
        if m[k] == nil then
            if visit(k, n, m, s) then
                return nil, "There is a circular dependency in the graph. It is not possible to derive a topological sort."
            end
        end
    end
    return s
end

-- Builds a graph for plugin dependencies and resolves it
local function topsort_plugins(plugins_meta, int_idx_plugins, phase)
    local graph = tsort.new()
    phase = phase or "access"

    for _, meta in pairs(int_idx_plugins) do
      local cfg = meta.config
      local plugin = meta.plugin
      local plugin_name = plugin.name
      local before = nil
      local after = nil
      if cfg.ordering then
        if cfg.ordering.before then
          before = cfg.ordering.before[phase]
        end
        if cfg.ordering.after then
          after = cfg.ordering.after[phase]
        end
      end

      -- This token describes a list of plugins that this plugin has a dependency to.
      if after then
        -- iterate over plugins that needs to run after `plugin_name`
        for _, iter_after in pairs(after) do
          -- Add node to graph (reversed)
          kong.log.debug("Plugin ", plugin_name, " depends on ", iter_after)
          local dependency = plugins_meta[iter_after] or ""
          if dependency == "" then
            kong.log.info("Plugin ", plugin_name, " has a dependency to a non-existing plugin. Cannot build graph")
          end
          graph:add(dependency, plugins_meta[plugin_name])
        end
      end

      -- This token describes a list of plugins that have a dependency on this plugin.
      if before then
        for _, iter_before in pairs(before) do
          -- Add node to graph
          local dependency = plugins_meta[iter_before] or ""
          if not dependency then
            kong.log.info("Plugin ", plugin_name, " has a dependency to a non-existing plugin. Cannot build graph")
          end
          kong.log.debug("Plugin ", plugin_name, " is dependent on ", iter_before)
          graph:add(plugins_meta[plugin_name], dependency)
        end
      end

      -- graphs without an edge
      if before == nil and after == nil then
        kong.log.debug("Plugin ", plugin_name, " has no incomming edges")
        graph:add(plugins_meta[plugin_name], "")
      end
    end
    
    return graph:sort()
end


return topsort_plugins
