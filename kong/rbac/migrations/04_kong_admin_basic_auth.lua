-- Migrate kong_admin from key-auth to basic-auth
local enums = require "kong.enterprise_edition.dao.enums"
local cjson = require "cjson"
local singletons = require "kong.singletons"


local function reset_context(workspaces)
  ngx.ctx.workspaces = workspaces
  singletons.dao = nil
end


return {
  kong_admin_basic_auth = {
    {
      name = "2018-11-08-000000_kong_admin_basic_auth",
      up = function (_, _, dao)
        -- look for kong_admin in default workspace,
        -- and create basic-auth credential there, too.
        local old_ws_scope = ngx.ctx.workspaces

        local ws_scope, err = dao.workspaces:find_all({ name = "default" })
        if err then
          return err
        end

        -- the dao passed in eventually uses a module (workspaces) that uses
        -- singletons.dao, which isn't initialized during migrations
        singletons.dao = dao

        ngx.ctx.workspaces = ws_scope

        local kong_admins, err = dao.consumers:find_all({
          username = "kong_admin",
          type = enums.CONSUMERS.TYPE.ADMIN,
        })
        if err then
          return err
        end

        local kong_admin = kong_admins[1]
        if not kong_admin then
          -- nothing to do here
          reset_context(old_ws_scope)
          return
        end

        local creds, err = dao.basicauth_credentials:find_all({
          consumer_id = kong_admin.id,
        })
        if err then
          return err
        end

        -- add cred only if not present
        if creds[1] then
          reset_context(old_ws_scope)
          return
        end

        -- the password is the key of the key_auth credential
        local credentials, err = dao.keyauth_credentials:find_all({
          consumer_id = kong_admin.id
        })
        if err then
          return err
        end

        local keyauth_cred = credentials[1]
        if not keyauth_cred then
          reset_context(old_ws_scope)
          return
        end

        local credential, err = dao.basicauth_credentials:insert({
          consumer_id = kong_admin.id,
          username = "kong_admin",
          password = keyauth_cred.key,
        })
        if err then
          return err
        end

        -- add creds to the common lookup table
        local _, err = dao.credentials:insert({
          id = credential.id,
          consumer_id = credential.consumer_id,
          consumer_type = enums.CONSUMERS.TYPE.ADMIN,
          plugin = "basic-auth",
          credential_data = tostring(cjson.encode(credential)),
        })
        if err then
          return err
        end

        reset_context(old_ws_scope)
      end
    }
  }
}

