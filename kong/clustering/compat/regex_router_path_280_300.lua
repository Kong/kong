-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local gsub = string.gsub
local sub = string.sub

local ipairs = ipairs
local re_find = ngx.re.find

-- We do not percent decode route.path after 3.0, so here we do 1 last time for them
local function revert_normalize(path)
  return gsub(path, "%%", "%25")
end

local function is_regex(path)
  return sub(path, 1, 1) == "~"
end

local function considered_regex_by_old_dp(path)
  return not (re_find(path, [[[a-zA-Z0-9\.\-_~/%]*$]], "ajo"))
end

local function escape_regex(path)
  return gsub(path, [[([%-%.%+%[%]%(%)%$%^%?%*%\%|%{%}])]], [[\%1]])
end

local function migrate_regex(reg)
  return revert_normalize(sub(reg, 2))
end

local function migrate(config_table)
  if not config_table.routes then
    return
  end

  for _, route in ipairs(config_table.routes) do
    local paths = route.paths
    for i, path in ipairs(paths) do
      if is_regex(path) then
        paths[i] = migrate_regex(path)

      elseif considered_regex_by_old_dp(path) then
        paths[i] = escape_regex(path)
      end
    end
  end
end

return migrate
