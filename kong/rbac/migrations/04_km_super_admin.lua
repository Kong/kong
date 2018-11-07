local utils = require "kong.tools.utils"
local enums = require "kong.enterprise_edition.dao.enums"
local cjson = require "cjson"


-- we provide a default username and password so that customers can
-- configure their users without requiring the "invite user" email
-- workflow. KONG_RBAC_INITIAL_ADMIN_PASS is a mouthful and is a
-- previously-undocumented feature, so we're also offering and
-- documenting KONG_PASSWORD
local username = "km_super_admin"
local password = os.getenv("KONG_PASSWORD") or
                 os.getenv("KONG_RBAC_INITIAL_ADMIN_PASS")

-- this migration runs after core and plugin migrations due to dependency on
-- basic-auth plugin. see kong.dao.factory.run_migrations().
return {
  bootstrap = {
    {
      name = "2018-11-05-000008_km_super_admin",
      up = function (_, _, dao)
        if not password or password == "" then
          return
        end

        -- add bootstrap user to default workspace
        local default_ws, err = dao.workspaces:find_all({
          name = "default",
        })

        if err then
          return err
        end

        default_ws = default_ws[1]
        if not default_ws then
          return "no default workspace found"
        end

        local old_ws = ngx.ctx.workspaces
        ngx.ctx.workspaces = { default_ws }

        -- note: this rbac_user is not meant to be used outside the context
        -- of the admin application. So its user_token doesn't necessarily
        -- have to be the same as the user's password, nor do they have to
        -- stay in sync.
        local rbac_user, err = dao.rbac_users:insert({
          id = utils.uuid(),
          name = username,
          user_token = utils.uuid(),
          enabled = true,
          comment = "Kong Manager Super User - for bootstrapping only",
        })

        if err then
          return err
        end

        -- make a super-admin
        local role, err = dao.rbac_roles:find_all({ name = "super-admin" })

        if err then
          return err
        end

        role = role[1]
        if not role then
          return "no super-admin role found"
        end

        local _, err = dao.rbac_user_roles:insert({
          user_id = rbac_user.id,
          role_id = role.id
        })

        if err then
          return err
        end

        local consumer, err = dao.consumers:insert({
          username = username,
          custom_id = username, -- this user is not externally linked
          type = enums.CONSUMERS.TYPE.ADMIN,
          status = enums.CONSUMERS.STATUS.APPROVED,
        })

        if err then
          return err
        end

        -- add mapping
        _, err = dao.consumers_rbac_users_map:insert({
          consumer_id = consumer.id,
          user_id = rbac_user.id,
        })

        if err then
          return err
        end

        -- add creds
        local credential, err = dao.basicauth_credentials:insert({
          consumer_id = consumer.id,
          username = username,
          password = password,
        })

        if err then
          return err
        end

        -- add creds again
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

        ngx.ctx.workspaces = old_ws
      end
    }
  }
}
