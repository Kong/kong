-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local log = ngx.log
local WARN = ngx.WARN
local utils = require("kong.tools.utils")

local rbac_roles = {}

function rbac_roles:cache_key(id, arg2, arg3, arg4, arg5, ws_id)
  if type(id) == "table" then
    id = id.id
  end

  if utils.is_valid_uuid(id) then
    -- Always return the cache_key without a workspace
    return "rbac_roles:" .. id .. ":::::"
  end

  return self.super.cache_key(self, id, arg2, arg3, arg4, arg5, ws_id)
end

function rbac_roles:filter_page(_, size, offset, options)
  options = options or {}
  options.filter = type(options.filter) == "function"
    and options.filter or function(row) return row end

  size = size or options.size or 100

  local page, err, err_t, new_offset
  local rows = {}
  local iterations = 0
  local MAX_ITERATIONS = 1000

  repeat
    page, err, err_t, new_offset = self:page(size, offset, options)
    if err_t then
      return nil, err, err_t
    end

    for i, row in ipairs(page) do
      local valid_row = options.filter(row)
      if valid_row and next(valid_row) then
        table.insert(rows, valid_row)

        -- current page is full
        if #rows == size then
          -- If we are stopping in the middle of a db page,
          -- our new_offset from self:page is incorrect.
          -- We need to recalculate new_offset from where
          -- we stopped.
          if i ~= #page then
            _, _, _, new_offset = self:page(i, offset, options)
          end

          return rows, nil, nil, new_offset
        end
      end
    end


    offset = new_offset
    iterations = iterations + 1
  until (not offset or iterations >= MAX_ITERATIONS)

  if iterations >= MAX_ITERATIONS  then
    log(WARN, "unable to retrieve full page of rbac_roles after ", MAX_ITERATIONS, " iterations")
  end

  return rows
end


return rbac_roles
