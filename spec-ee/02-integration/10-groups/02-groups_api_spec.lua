local workspaces = require "kong.workspaces"
local helpers	   = require "spec.helpers"
local cjson 	   = require "cjson"
local utils 	   = require "kong.tools.utils"
local ee_helpers = require "spec-ee.helpers"

local client
local db

local function truncate_tables(db)
  db:truncate("workspaces")
  db:truncate("rbac_roles")
  db:truncate("groups")
  db:truncate("group_rbac_roles")
end

for _, strategy in helpers.each_strategy() do
  describe("Groups API #" .. strategy, function()
    local function get_request(url, token)
      if not token then 
        token ="letmein-default" 
      end

      local json = assert.res_status(200, assert(client:send {
        method = "GET",
        path = url,
        headers = {
          ["Content-Type"] = "application/json",
          ["Kong-Admin-Token"] = token,
        },
      }))

      local res = cjson.decode(json)

      return res, res.data and #res.data or 0
    end

    lazy_setup(function()
      helpers.stop_kong()

      _, db = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database  = strategy,
        smtp_mock = true,
        admin_gui_auth = "basic-auth",
        enforce_rbac = "on",
        
        admin_gui_auth_config = "{ \"hide_credentials\": true }",
      }))

      client = assert(helpers.admin_client())

      assert(db.groups)
      assert(db.group_rbac_roles)
    end)

    lazy_teardown(function()
      truncate_tables(db)

      helpers.stop_kong()
      if client then
        client:close()
      end
    end)

    describe("/groups :", function()
      local function insert_group()
        local submission = { name = "test_group_" .. utils.uuid() }
        local json = assert.res_status(201, assert(client:send {
          method = "POST",
          path = "/groups",
          body = submission,
          headers = {
            ["Content-Type"] = "application/json",
            ["Kong-Admin-Token"] = "letmein-default",
          }
        }))

        return cjson.decode(json)
      end

      local function check_delete(key)
        assert.res_status(204, assert(client:send {
          method = "DELETE",
          path = "/groups/" .. key,
          headers = {
            ["Kong-Admin-Token"] = "letmein-default",
          }
        }))
        
        local res = get_request("/groups")

        assert.same({}, res.data)
      end

      lazy_setup(function()
        ee_helpers.register_rbac_resources(db)
      end)

      lazy_teardown(function()
        db:truncate("rbac_roles")
      end)

      it("GET The endpoint should list groups entities as expected", function()
        local name = "test_group_" .. utils.uuid()
        local res

        assert(db.groups:insert{ name = name})
        res = get_request("/groups")

        assert.same(name, res.data[1].name)
      end)
      
      it("GET The endpoint should work with the 'offset' filter", function()
        local qty = 3

        db:truncate("groups")

        for i = 1, qty do
          assert(db.groups:insert{ name = "test_group_" .. utils.uuid()})
        end

        local res, count = get_request("/groups?size=" .. qty-1)
        local _, count_2 = get_request(res.next)

        assert.is_equal(qty, count + count_2)
      end)
      
      it("GET The endpoint should list a group by id", function()
        local res_insert = insert_group()
        
        local res_select = get_request("/groups/" .. res_insert.id)

        assert.same(res_insert, res_select)
      end)

      it("GET The endpoint should list a group by name", function()
        local res_insert = insert_group()
        
        local res_select = get_request("/groups/" .. res_insert.name)

        assert.same(res_insert, res_select)
      end)

      it("GET The endpoint should return '404' when the group not found", function()
        assert.res_status(404, assert(client:send {
          method = "GET",
          path = "/groups/" .. utils.uuid(),
          headers = {
            ["Kong-Admin-Token"] = "letmein-default",
          }
        }))
      end)

      it("POST The endpoint should not create a group entity with out a 'name'", function()
        local submission = { comment = "create a group with out a name" }

        assert.res_status(400, assert(client:send {
          method = "POST",
          path = "/groups",
          body = submission,
          headers = {
            ["Content-Type"] = "application/json",
            ["Kong-Admin-Token"] = "letmein-default",
          },
        }))
      end)

      it("POST The endpoint should create a group entity as expected", function()
        insert_group()
      end)

      it("PATCH The endpoint should update a group entity as expected", function()
        local comment = "now we have comment"
        local submission = { name = "test_group_" .. utils.uuid() }
        -- create a group
        local json_create = assert.res_status(201, assert(client:send {
          method = "POST",
          path = "/groups",
          body = submission,
          headers = {
            ["Content-Type"] = "application/json",
            ["Kong-Admin-Token"] = "letmein-default",
          },
        }))
        local res_create = cjson.decode(json_create)

        -- update a group
        local json_update = assert.res_status(200, assert(client:send {
          method = "PATCH",
          path = "/groups/" .. res_create.id,
          body = {
            comment = comment
          },
          headers = {
            ["Content-Type"] = "application/json",
            ["Kong-Admin-Token"] = "letmein-default",
          },
        }))
        local res_update = cjson.decode(json_update)

        -- check group has been updated
        assert.same(ngx.null, res_create.comment)
        assert.same(comment, res_update.comment)
      end)

      it("DELETE The endpoint should delete a group entity by id", function()
        local group

        db:truncate("groups")
        group = insert_group()
        check_delete(group.id)
      end)

      it("DELETE The endpoint should delete a group entity by name", function()
        local group

        db:truncate("groups")
        group = insert_group()
        check_delete(group.name)
      end)
    end)

    describe("/groups/:groups/roles : ", function()
      local function register_resources(db, ws)
        local _, user_role, err = ee_helpers.register_rbac_resources(db, ws)
        -- ensure resources
        assert.is.falsy(err)
      
        return user_role.role, "letmein-" .. ws
      end

      local function insert_entities(workspace)
        local group = assert(db.groups:insert{ name = "test_group_" .. utils.uuid()})
        local role, token

        if not workspace then
          workspace = assert(db.workspaces:insert({ name = "test_ws_" .. utils.uuid()}))
          workspaces.run_with_ws_scope({ workspace }, function()
            role, token = register_resources(db, workspace.name)
          end)
        else
          workspaces.run_with_ws_scope({ workspace }, function()
            role = assert(db.rbac_roles:insert(
              { name = "test_role_" .. utils.uuid() }
            ))
          end)

          token = "letmein-" .. workspace.name
        end

        return group, role, workspace, token
      end

      local function insert_mapping(group, role, workspace)

        local mapping = {
          rbac_role = { id = role.id },
          workspace = { id = workspace.id },
          group 	  = { id = group.id },
        }

        workspaces.run_with_ws_scope({ workspace }, function()
          assert(db.group_rbac_roles:insert(mapping))
        end)
      end

      describe("GET", function()
        local group, role, workspace, token

        lazy_setup(function()
          group, role, workspace, token = insert_entities()
          insert_mapping(group, role, workspace)
        end)

        lazy_teardown(function()
          db:truncate("rbac_roles")
        end)

        it("The endpoint should list roles by a group id", function()
          local res = get_request("/groups/" .. group.id .. "/roles", token)

          assert.same(res.data[1].group.id, group.id)
          assert.same(res.data[1].workspace.id, workspace.id)
          assert.same(res.data[1].rbac_role.id, role.id)
        end)

        it("The endpoint should list roles by a group name", function()
          local res = get_request("/groups/" .. group.name .. "/roles", token)

          assert.same(res.data[1].group.id, group.id)
          assert.same(res.data[1].workspace.id, workspace.id)
          assert.same(res.data[1].rbac_role.id, role.id)
        end)

        it("The endpoint should work with the 'offset' filter", function()
          local qty = 3

          for i = 1, qty do
            local _, _role = insert_entities(workspace)
            -- insert mapping with one group
            insert_mapping(group, _role, workspace)
          end

          local res_1 = get_request("/groups/" .. group.id .. "/roles?size=" .. qty-1, token)
          local res_2 = get_request(res_1.next, token)

          -- it's qty+1  since,
          -- there is 1 mapping created during the "before_each"
          assert.is_equal(qty + 1, #res_1.data + #res_2.data)
        end)
      end)

      describe("POST", function()
        local group, role, workspace, token

        local function check_create(res_code, key, _group, _role, _workspace)
          local json = assert.res_status(res_code, assert(client:send {
            method = "POST",
            path = "/groups/" .. key .. "/roles",
            body = {
              rbac_role_id = _role.id,
              workspace_id = _workspace.id,
            },
            headers = {
              ["Content-Type"] = "application/json",
              ["Kong-Admin-Token"] = token,
            },
          }))
          
          if res_code ~= 201 then 
            return nil
          end

          local res = cjson.decode(json)

          assert.same(res.group.id, _group.id)
          assert.same(res.workspace.id, _workspace.id)
          assert.same(res.rbac_role.id, _role.id)
        end
        
        lazy_setup(function()
          group, role, workspace, token = insert_entities()
          insert_mapping(group, role, workspace)
        end)

        lazy_teardown(function()
          db:truncate("rbac_roles")
        end)

        it("The endpoint should not create a mapping with incorrect params", function()
          local _group, _role = insert_entities(workspace)

          do
            -- body params need to be correct
            local json_no_workspace = assert.res_status(400, assert(client:send {
              method = "POST",
              path = "/groups/" .. _group.id .. "/roles",
              body = {
                rbac_role_id = _role.id,
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Kong-Admin-Token"] = token,
              },
            }))
            assert.same("must provide the workspace_id", cjson.decode(json_no_workspace).message)

            local json_no_role = assert.res_status(400, assert(client:send {
              method = "POST",
              path = "/groups/" .. _group.id .. "/roles",
              body = {
                workspace_id = workspace.id,
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Kong-Admin-Token"] = token,
              },
            }))
            assert.same("must provide the rbac_role_id", cjson.decode(json_no_role).message)
          end

          do
            -- entities need to be found
            assert.res_status(404, assert(client:send {
              method = "POST",
              path = "/groups/" .. _group.id .. "/roles",
              body = {
                workspace_id = utils.uuid(),
                rbac_role_id = _role.id,
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Kong-Admin-Token"] = token,
              },
            }))

            assert.res_status(404, assert(client:send {
              method = "POST",
              path = "/groups/" .. _group.id .. "/roles",
              body = {
                workspace_id = workspace.id,
                rbac_role_id = utils.uuid(),
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Kong-Admin-Token"] = token,
              },
            }))
          end
        end)

        it("The endpoint should not create a mapping with incorrect ids", function() 
          local _role = assert(db.rbac_roles:insert{ name = "test_role_" .. utils.uuid()})
          local res_roles_default = get_request("/default/rbac/roles", token)

          assert.same(_role.id, res_roles_default.data[1].id)
          check_create(404, group.id, group, _role, workspace)	
        end)

        it("The endpoint should create a mapping with correct params by id", function()
          local _group, _role = insert_entities(workspace)
          check_create(201, _group.id, _group, _role, workspace)
        end)

        it("The endpoint should create a mapping with correct params by group name", function()
          local _group, _role = insert_entities(workspace)
          check_create(201, _group.name, _group, _role, workspace)
        end)
      end)

      describe("DELETE", function()
        local group, role, workspace, token

        local function check_delete(key)
          assert.res_status(204, assert(client:send {
            method = "DELETE",
            path = "/groups/" .. key .. "/roles",
            body = {
              rbac_role_id = role.id,
              workspace_id = workspace.id,
            },
            headers = {
              ["Content-Type"] = "application/json",
              ["Kong-Admin-Token"] = token,
            },
          }))

          local res = get_request("/groups/" .. group.id .. "/roles", token)

          assert.same({}, res.data)
        end

        before_each(function()
          group, role, workspace, token = insert_entities(workspace)
          insert_mapping(group, role, workspace)
        end)

        lazy_teardown(function()
          db:truncate("rbac_roles")
        end)

        it("The endpoint should delete a mapping with correct params by id", function()
          check_delete(group.id)
        end)

        it("The endpoint should delete a mapping with correct params by group name", function()
          check_delete(group.name)
        end)
      end)
    end)
  end)
end
