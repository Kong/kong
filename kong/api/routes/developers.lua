local constants    = require "kong.constants"
local utils        = require "kong.tools.utils"
local endpoints    = require "kong.api.endpoints"
local ws_helper    = require "kong.workspaces.helper"
local portal_smtp_client = require "kong.portal.emails"
local crud_helpers       = require "kong.portal.crud_helpers"
local enums              = require "kong.enterprise_edition.dao.enums"

local unescape_uri = ngx.unescape_uri
local ws_constants = constants.WORKSPACE_CONFIG


local function find_developer(db, developer_pk)
  local id = unescape_uri(developer_pk)
  if utils.is_valid_uuid(id) then
    return db.developers:select({ id = developer_pk })
  end

  return db.developers:select_by_email(developer_pk)
end


local function update_developer(db, developer_pk, params)
  local id = unescape_uri(developer_pk)
  if utils.is_valid_uuid(id) then
    return db.developers:update({ id = developer_pk }, params)
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
    GET = function(self, db, helpers, parent)
      local size = self.params.size or 100
      local offset = self.params.offset

      self.params.offset = nil
      self.params.size = nil
      self.params.status = tonumber(self.params.status)

      local developers, err, err_t = db.developers:select_all(self.params)
      if err then
        return endpoints.handle_error(err_t)
      end

      local paginated_results, _, err_t = crud_helpers.paginate(
        self, '/developers', developers, size, offset
      )

      if not paginated_results then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_OK(paginated_results)
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
    PATCH = function(self, db, helpers)
      local developer_pk = self.params.developers
      self.params.developers = nil

      -- save previous status
      local developer = find_developer(db, developer_pk)
      if not developer then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local previous_status = developer.status

      local developer, _, err_t = update_developer(db, developer_pk, self.params)
      if not developer then
        return endpoints.handle_error(err_t)
      end

      local res = { developer = developer }
      if developer.status == enums.CONSUMERS.STATUS.APPROVED and
         developer.status ~= previous_status and
         previous_status ~= enums.CONSUMERS.STATUS.REVOKED then

        local portal_emails = portal_smtp_client.new()
        local email_res, err = portal_emails:approved(developer.email)
        if err then
          if err.code then
            return helpers.responses.send(err.code, {message = err.message})
          end

          return helpers.yield_error(err)
        end

        res.email = email_res
      end

      return helpers.responses.send_HTTP_OK(res)
    end,
  },

  ["/developers/:email_or_id/plugins/"] = {
    GET = function(self, db, helpers)
      local developer = find_developer(db, self.params.email_or_id)
      if not developer then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local consumer = developer.consumer
      local plugins, err, err_t = db.plugins:select_all({ consumer = consumer })
      if err then
        return endpoints.handle_error(err_t)
      end

      helpers.responses.send_HTTP_OK(plugins)
    end,

    POST = function(self, db, helpers)
      local developer = find_developer(db, self.params.email_or_id)
      if not developer then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.params.email_or_id = nil
      self.params.consumer = developer.consumer

      local ok, _, err_t = db.plugins:insert(self.params)
      if not ok then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_CREATED(ok)
    end,

    -- TODO DEVX: Implement PUT if time allows
    -- PUT = function(self, dao_factory, helpers)
    --   find_developer(self, dao_factory, helpers)
    --   self.params.consumer_id = self.consumer.id

    --   crud.put(self.params, dao_factory.plugins)
    -- end
  },

  ["/developers/:email_or_id/plugins/:id"] = {
    GET = function(self, db, helpers)
      local developer = find_developer(db, self.params.email_or_id)

      if not developer then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local consumer = developer.consumer
      local plugin, _, err_t = db.plugins:select_all({
        consumer = { id = consumer.id },
        id = self.params.id
      })

      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not next(plugin) then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      return helpers.responses.send_HTTP_OK(plugin)
    end,

    PATCH = function(self, db, helpers)
      local developer = find_developer(db, self.params.email_or_id)
      if not developer then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.params.email_or_id = nil

      local consumer = developer.consumer
      local plugins, _, err_t = db.plugins:select_all({
        consumer = { id = consumer.id },
        id = self.params.id
      })

      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not next(plugins) then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.params.id = nil

      local plugin = plugins[1]
      local ok, _, err_t = db.plugins:update({ id = plugin.id }, self.params)
      if not ok then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_OK(ok)
    end,

    DELETE = function(self, db, helpers)
      local developer = find_developer(db, self.params.email_or_id)
      if not developer then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local consumer = developer.consumer
      local plugins, _, err_t = db.plugins:select_all({
        consumer = { id = consumer.id },
        id = self.params.id
      })

      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not next(plugins) then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.params.id = nil
      local plugin = plugins[1]
      local ok, _, err_t = db.plugins:delete({ id = plugin.id })
      if not ok then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_NO_CONTENT()
    end
  },

  ["/portal/invite"] = {
    POST = function(self, db, helpers)
      if not self.params.emails or next(self.params.emails) == nil then
        return helpers.responses.send_HTTP_BAD_REQUEST("emails param required")
      end
      local portal_emails = portal_smtp_client.new()
      local res, err = portal_emails:invite(self.params.emails)
      if err then
        if err.code then
          return helpers.responses.send(err.code, {message = err.message})
        end

        return helpers.yield_error(err)
      end

      return helpers.responses.send_HTTP_OK(res)
    end
  },
}
