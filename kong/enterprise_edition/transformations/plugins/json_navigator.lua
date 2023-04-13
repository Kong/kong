-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ngx_re = require("ngx.re")
local tablex = require("pl.tablex")

local table_insert = table.insert
local table_remove = table.remove
local type = type
local ipairs = ipairs
local tonumber = tonumber
local null = ngx.null
local EMPTY = tablex.readonly({})

local _M = {}

local function is_present(str)
  return str and str ~= "" and str ~= null
end


local function _navigate_and_apply(ctx, json, path, fn, opts)
  local head, index, tail

  if opts.dots_in_keys then
    head = path
  else
    -- Split into a table with three values, e.g. Results[*].info.name becomes {"Results", "[*]", "info.name"}
    local res = ngx_re.split(path, [[(?:\[([\d|\*]*)\])?\.]], "jo", nil, 2)
    if res then
      head = res[1]
      if res[2] and res[3] then
        -- Extract index, e.g. "2" from "[2]"
        index = res[2]
        tail = res[3]

      else
        tail = res[2]
      end
    end
  end

  if type(json) == "table" then
    if index == "*" then
      -- Iterate array
      local array = json
      local head_visit = false
      if is_present(head) then
        table_insert(ctx.paths, head)
        array = json[head]
        head_visit = true
      end

      for k, v in ipairs(array or EMPTY) do
        if type(v) == "table" then
          table_insert(ctx.paths, k)
          ctx.index = k
          _navigate_and_apply(ctx, v, tail, fn, opts)
          ctx.index = nil
          table_remove(ctx.paths)
        end
      end

      if head_visit then
        table_remove(ctx.paths)
      end

    elseif is_present(index) then
      -- Access specific array element by index
      index = tonumber(index)
      local element = json
      local head_visit = false

      if is_present(head) and type(json[head]) == "table" then
        table_insert(ctx.paths, head)
        element = json[head]
        head_visit = true
      end

      element = element[index]

      table_insert(ctx.paths, index)
      ctx.index = index
      _navigate_and_apply(ctx, element, tail, fn, opts)
      ctx.index = nil
      table_remove(ctx.paths)
      if head_visit then
        table_remove(ctx.paths)
      end

    elseif is_present(tail) then
      -- Navigate into nested JSON

      if opts.create_inexistent_parent then
        if json[head] == nil then
          json[head] = {}
        end
      end

      table_insert(ctx.paths, head)
      _navigate_and_apply(ctx, json[head], tail, fn, opts)
      table_remove(ctx.paths)

    elseif is_present(head) then
      -- Apply passed-in function
      fn(json, head, ctx)

    end
  end
end


--- Navigate json to the value(s) pointed to by path and apply function fn to it.
_M.navigate_and_apply = function(json, path, fn, opts)
  opts = opts or EMPTY
  local ctx = {
    paths = {},
  }
  return _navigate_and_apply(ctx, json, path, fn, opts)
end


return _M
