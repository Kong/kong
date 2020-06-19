-- Migrate kong_admin from key-auth to basic-auth
local enums = require "kong.enterprise_edition.dao.enums"
local cjson = require "cjson"
local singletons = require "kong.singletons"


local workspaces
local singletons_dao


local function setup(dao)
  workspaces = ngx.ctx.workspaces

  -- the dao passed in eventually uses a module (workspaces) that uses
  -- singletons.dao, which isn't initialized during migrations
  singletons_dao = singletons.dao
  singletons.dao = dao
end

local function teardown()
  ngx.ctx.workspaces = workspaces
  singletons.dao = singletons_dao
end


local function migrate(dao, password)
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
    return
  end

  local credential, err = dao.basicauth_credentials:insert({
    consumer_id = kong_admin.id,
    username = "kong_admin",
    password = password,
  })

  -- only report error if it's not a "record already exists" one
  if err and not string.match(tostring(err), "exists") then
    return err
  end

  if credential then
    -- add creds to the common lookup table
    local _, err = singletons.db.credentials:insert({
      id = credential.id,
      consumer = { id = credential.consumer_id, },
      consumer_type = enums.CONSUMERS.TYPE.ADMIN,
      plugin = "basic-auth",
      credential_data = tostring(cjson.encode(credential)),
    })
    if err then
      return err
    end
  end
end


return {
  kong_admin_basic_auth = {
    {
      name = "2018-11-08-000000_kong_admin_basic_auth",
      up = function (_, _, dao)
        -- see if there's a password to use
        local password = os.getenv("KONG_PASSWORD")
        if not password then
          return
        end
      
        setup(dao)

        -- look for kong_admin in default workspace,
        -- and create basic-auth credential there, too.
        local ws_scope, err = dao.workspaces:find_all({ name = "default" })
        if err then
          return err
        end

        ngx.ctx.workspaces = ws_scope

        local err = migrate(dao, password)
        teardown()

        if err then
          return err
        end
      end
    }
  }
}

