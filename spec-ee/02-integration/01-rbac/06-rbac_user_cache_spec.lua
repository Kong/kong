local cjson = require "cjson.safe"
local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"
local workspaces = require "kong.workspaces"
local utils = require "kong.tools.utils"

local client
local db, dao
local get_admin_cookie_basic_auth = ee_helpers.get_admin_cookie_basic_auth

local function truncate_tables(db)
  db:truncate("workspace_entities")
  db:truncate("consumers")
  db:truncate("rbac_user_roles")
  db:truncate("rbac_roles")
  db:truncate("rbac_users")
  db:truncate("admins")
end

local function setup_ws_defaults(dao, db, workspace)
  if not workspace then
    workspace = workspaces.DEFAULT_WORKSPACE
  end

  -- setup workspace and register rbac default roles
  local ws, err = db.workspaces:insert({
      name = workspace,
  }, { quiet = true })

  if err then
    ws = db.workspaces:select_by_name(workspace)
  end

  ngx.ctx.workspaces = { ws }

  -- create a record we can use to test inter-workspace calls
  assert(db.services:insert({  host = workspace .. "-example.com", }))

  ee_helpers.register_rbac_resources(db, workspace)

  return ws
end


local function admin(db, workspace, name, role, email)
  return workspaces.run_with_ws_scope({workspace}, function ()
    local admin = db.admins:insert({
      username = name,
      email = email,
      status = 4, -- TODO remove once admins are auto-tagged as invited
    })

    local role = db.rbac_roles:select_by_name(role)
    db.rbac_user_roles:insert({
      user = { id = admin.rbac_user.id },
      role = { id = role.id }
    })

    local raw_user_token = utils.uuid()
    assert(db.rbac_users:update({id = admin.rbac_user.id}, {
      user_token = raw_user_token
    }))
    admin.rbac_user.raw_user_token = raw_user_token

    return admin
  end)
end

for _, strategy in helpers.each_strategy() do
  describe("RBAC user cache on #" .. strategy, function()
    local super_admin
    
    lazy_setup(function()
      _, db, dao = helpers.get_db_utils(strategy)
      truncate_tables(db)

      assert(helpers.start_kong({
        database   = strategy,
        admin_gui_auth = "basic-auth",
        enforce_rbac = "on",
        admin_gui_auth_config = "{ \"hide_credentials\": true }",
        rbac_auth_header = 'Kong-Admin-Token',
        smtp_mock = true,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      if client then
        client:close()
      end
    end)

    describe('#Cache Key:', function()
      local cache_key, cookie

      local function update_rbac_user_comment(db, id, str)
        workspaces.run_with_ws_scope({}, function ()
          assert(db.rbac_users:update({id = id},{
            comment = str
          }))

          assert.equal(
            db.rbac_users:select({id = id}).comment, 
            str
          )
        end)
      end
      
      local function check_cache(expected_status, cache_key, entity)
        local res = assert(client:send {
          method = "GET",
          path = "/cache/" .. cache_key,
          headers = {
            ["cookie"] = cookie,
            ["Kong-Admin-User"] = super_admin.username,
          },
        })
      
        local json = assert.res_status(expected_status, res)
        local body = cjson.decode(json)
        
        if type(entity) ~= "table" then return end

        for key, field in pairs(entity) do
          assert.equal(body[key], field)
        end
      end

      lazy_setup(function()
        client = assert(helpers.admin_client())

        local ws = setup_ws_defaults(dao, db, workspaces.DEFAULT_WORKSPACE)
        super_admin = admin(db, ws, 'mars', 'super-admin','test@konghq.com')
        
        assert(db.basicauth_credentials:insert {
          username    = super_admin.username,
          password    = "hunter1",
          consumer = {
            id = super_admin.consumer.id,
          },
        })

        cookie = get_admin_cookie_basic_auth(client, super_admin.username, 'hunter1')
        cache_key = db.rbac_users:cache_key(super_admin.rbac_user.id, '', '', '', '', true)
      end)

      lazy_teardown(function()
        if client then
          client:close()
        end
      end)

      it("rbac_user should be cached after a API call", function()
        local res = assert(client:send {
          method = "GET",
          path = "/",
          headers = {
            ["cookie"] = cookie,
            ["Kong-Admin-User"] = super_admin.username,
          },
        })

        assert.res_status(200, res)
        check_cache(200, cache_key)
      end)

      it("rbac_user cache should be update after update", function()
        local comment = "user has been modified"

        update_rbac_user_comment(db, super_admin.rbac_user.id, comment)
        helpers.wait_until(check_cache(200, cache_key, {comment = comment}), 10)
        
      end)
    end)
  end)
end
