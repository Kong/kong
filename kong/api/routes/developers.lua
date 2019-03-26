local utils = require "kong.tools.utils"
local endpoints = require "kong.api.endpoints"
local singletons = require "kong.singletons"
local constants  = require "kong.constants"
local ws_helper  = require "kong.workspaces.helper"
local enums      = require "kong.enterprise_edition.dao.enums"

local unescape_uri = ngx.unescape_uri
local ws_constants = constants.WORKSPACE_CONFIG


local function check_portal_status(helpers)
  if not singletons.configuration.portal then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end


local function update_developer(db, developer_pk, params)
  local id = unescape_uri(developer_pk)
  if utils.is_valid_uuid(id) then
    return db.developers:update(developer_pk, params)
  end

  return db.developers:update_by_email(developer_pk, params)
end


local function get_developer_status()
  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
  local auto_approve = ws_helper.retrieve_ws_config(ws_constants.PORTAL_AUTO_APPROVE, workspace)

  if auto_approve then
    return enums.CONSUMERS.STATUS.APPROVED
  end

  return enums.CONSUMERS.STATUS.PENDING
end


return {
  ["/developers"] = {
    before = function(self, db, helpers)
      check_portal_status(helpers)
    end,

    GET = function(self, db, helpers, parent)
      self.params.status = tonumber(self.params.status)

      local developers, err, err_t = db.developers:select_all(self.params)
      if err then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_OK({ data = developers })
    end,

    POST = function(self, db, helpers)
      if not self.params.status then
        self.params.status = get_developer_status()
      end

      local developer, _, err_t = db.developers:insert(self.params)
      if not developer then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_OK(developer)
    end,
  },

  ["/developers/:developers"] = {
    before = function(self, db, helpers)
      check_portal_status(helpers)
    end,

    PATCH = function(self, db, helpers, parent)
      local developer_pk = self.params.developers
      self.params.developers = nil

      local developer, _, err_t = update_developer(db, developer_pk, self.params)
      if not developer then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_OK(developer)
    end,
  }
}
