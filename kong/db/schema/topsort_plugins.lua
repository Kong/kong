-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local setmetatable = setmetatable
local ipairs = ipairs
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
local function topsort_plugins(plugins_hash, plugins_array, phase)
    local has_ordering
    local graph = tsort.new()
    phase = phase or "access"
    for _, meta in ipairs(plugins_array) do
      local cfg = meta.config
      local plugin_name = meta.plugin.name
      local before
      local after
      local ordering = cfg.ordering
      if ordering then
        after = ordering.after
        if after then
          after = after[phase]
        end
        before = ordering.before
        if before then
          before = before[phase]
        end
      end

      -- This token describes a list of plugins that this plugin has a dependency to.
      if after then
        -- iterate over plugins that needs to run after `plugin_name`
        for _, after_plugin_name in ipairs(after) do
          -- Add node to graph (reversed)
          kong.log.debug("Plugin ", plugin_name, " depends on ", after_plugin_name)
          local dependency = plugins_hash[after_plugin_name] or ""
          if dependency == "" then
            kong.log.info("Plugin ", plugin_name, " has a dependency to a non-existing plugin. Cannot build graph")
          elseif not has_ordering then
            has_ordering = true
          end
          graph:add(dependency, meta)
        end
      end

      -- This token describes a list of plugins that have a dependency on this plugin.
      if before then
        for _, before_plugin_name in ipairs(before) do
          -- Add node to graph
          local dependency = plugins_hash[before_plugin_name] or ""
          if not dependency then
            kong.log.info("Plugin ", plugin_name, " has a dependency to a non-existing plugin. Cannot build graph")
          elseif not has_ordering then
            has_ordering = true
          end
          kong.log.debug("Plugin ", plugin_name, " is dependent on ", before_plugin_name)
          graph:add(meta, dependency)
        end
      end

      -- graphs without an edge
      if before == nil and after == nil then
        kong.log.debug("Plugin ", plugin_name, " has no incoming edges")
        graph:add(meta, "")
      end
    end

    if has_ordering then
      return graph:sort()
    end

    return plugins_array
end


return topsort_plugins
