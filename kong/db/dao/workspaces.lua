-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local portal_helpers = require "kong.portal.dao_helpers"
local insert         = table.insert
local new_tab        = require "table.new"

local Workspaces = {}


local constants = require("kong.constants")
local lmdb = require("resty.lmdb")


local DECLARATIVE_DEFAULT_WORKSPACE_KEY = constants.DECLARATIVE_DEFAULT_WORKSPACE_KEY
local DECLARATIVE_DEFAULT_WORKSPACE_ID = constants.DECLARATIVE_DEFAULT_WORKSPACE_ID


function Workspaces:insert(entity, options)
  local entity, err = portal_helpers.set_portal_conf({}, entity)
  if not entity then
    return kong.response.exit(400, { message = err })
  end

  return self.super.insert(self, entity, options)
end
local function valid_row(endpoints_perms, row)
  if endpoints_perms["*"] or endpoints_perms[row.name] then
    return true
  end
end

function Workspaces:page_by_rbac(_, size, offset, options)
  local rbac = ngx.ctx.rbac
  if not rbac then
    return self:page(size, offset, options)
  end
  -- request fetch all data
  size = size or options.size or 100
  local page, err, err_t, new_offset

  local tab_size = size
  if tab_size > 100 then
    tab_size = 100
  end
  local rows = new_tab(tab_size, 0)
  
  repeat
    page, err, err_t, new_offset = self:page(size, offset, options)
    if err_t then
      return nil, err, err_t
    end
    for i, row in ipairs(page) do
      if next(row) and valid_row(rbac.endpoints_perms, row) then
        insert(rows, row)
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
  until (not offset)

  return rows, nil, nil, new_offset
end

function Workspaces:update(workspace_pk, entity, options)
  local ws, err, err_t = self.db.workspaces:select({ id = workspace_pk.id })
  if err then
    return nil, err, err_t
  end

  local entity, err = portal_helpers.set_portal_conf(ws, entity)
  if not entity then
    return kong.response.exit(400, { message = err })
  end

  return self.super.update(self, { id = ws.id }, entity, options)
end


function Workspaces:update_by_name(workspace_name, entity, options)
  local ws, err, err_t = self.db.workspaces:select_by_name(workspace_name)
  if err then
    return nil, err, err_t
  end

  local entity, err = portal_helpers.set_portal_conf(ws, entity)
  if not entity then
    return kong.response.exit(400, { message = err })
  end

  return self.super.update(self, { id = ws.id }, entity, options)
end


function Workspaces:truncate()
  self.super.truncate(self)
  if kong.configuration.database == "off" then
    return true
  end

  local default_ws, err = self:insert({ name = "default" })
  if err then
    kong.log.err(err)
    return
  end

  ngx.ctx.workspace = default_ws.id
  kong.default_workspace = default_ws.id
end


function Workspaces:select_by_name(key, options)
  if kong.configuration.database == "off" and key == "default" then
    -- TODO: Currently, only Kong workers load the declarative config into lmdb.
    -- The Kong master doesn't get the default workspace from lmdb, so we
    -- return the default constant value. It would be better to have the
    -- Kong master load the declarative config into lmdb in the future.
    --
    -- it should be a table, not a single string
    return { id = lmdb.get(DECLARATIVE_DEFAULT_WORKSPACE_KEY) or DECLARATIVE_DEFAULT_WORKSPACE_ID, }
  end

  return self.super.select_by_name(self, key, options)
end


return Workspaces
