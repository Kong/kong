local helpers	= require "spec.helpers"
local cjson 	= require "cjson"
local utils 	= require "kong.tools.utils"

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
    local function get_request(url)
      local json = assert.res_status(200, assert(client:send {
        method = "GET",
        path = url,
      }))

      local res = cjson.decode(json)

      return res, #res.data
    end

    lazy_setup(function()
      helpers.stop_kong()

      _, db = helpers.get_db_utils(strategy)
      
      assert(helpers.start_kong({
        database  = strategy,
        smtp_mock = true,
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
      it("The endpoint should list groups entities as expected", function()
        local name = "test_group_" .. utils.uuid()
        local res

        assert(db.groups:insert{ name = name})
        res = get_request("/groups")

        assert.same(name, res.data[1].name)
      end)
      
      it("The endpoint should work with the 'offset' filter", function()
        local qty = 3
        
        db:truncate("groups")

        for i = 1, qty do
          assert(db.groups:insert{ name = "test_group_" .. utils.uuid()})
        end
        
        local res, count = get_request("/groups?size=" .. qty-1)
        local _, count_2 = get_request(res.next)
       
        assert.is_equal(qty, count + count_2)
      end)
      
      it("The endpoint should not create a group entities with out a 'name'", function()
        local submission = { comment = "create a group with out a name" }

        assert.res_status(400, assert(client:send {
          method = "POST",
          path = "/groups",
          body = submission,
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
      end)

      it("The endpoint should create a group entities as expected", function()
        local submission = { name = "test_group_" .. utils.uuid() }
        assert.res_status(201, assert(client:send {
          method = "POST",
          path = "/groups",
          body = submission,
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
      end)

      it("The endpoint should update a group entities as expected", function()
        local comment = "now we have comment"
        local submission = { name = "test_group_" .. utils.uuid() }
        -- create a group
        local json_create = assert.res_status(201, assert(client:send {
          method = "POST",
          path = "/groups",
          body = submission,
          headers = {
            ["Content-Type"] = "application/json",
          }
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
          }
        }))
        local res_update = cjson.decode(json_update)

        -- check group has been updated
        assert.same(ngx.null, res_create.comment)
        assert.same(comment, res_update.comment)
      end)
    end)

    describe("/groups/:groups/roles :", function()
      local group, role, workspace

      local function insert_entities()
        local group = assert(db.groups:insert{ name = "test_group_" .. utils.uuid()})
        local role = assert(db.rbac_roles:insert{ name = "test_role_" .. utils.uuid()})
        local workspace = assert(db.workspaces:insert{ name = "test_workspace_" .. utils.uuid()})
        
        return group, role, workspace
      end

      local function insert_mapping(group, role, workspace)
        
        local mapping = {
          rbac_role = { id = role.id },
          workspace = { id = workspace.id },
          group 	  = { id = group.id },
        }

        assert(db.group_rbac_roles:insert(mapping))
      end

      describe("GET", function()
        before_each(function()
          group, role, workspace = insert_entities()
          insert_mapping(group, role, workspace)
        end)

        it("The endpoint should list roles by a group id", function()
          local json = assert.res_status(200, assert(client:send {
            method = "GET",
            path = "/groups/" .. group.id .. "/roles",
          }))
  
          local res = cjson.decode(json)

          assert.same(res.data[1].group.id, group.id)
          assert.same(res.data[1].workspace.id, workspace.id)
          assert.same(res.data[1].rbac_role.id, role.id)
        end)
  
        it("The endpoint should list roles by a group name", function()
          local json = assert.res_status(200, assert(client:send {
            method = "GET",
            path = "/groups/" .. group.name .. "/roles",
          }))
  
          local res = cjson.decode(json)
  
          assert.same(res.data[1].group.id, group.id)
          assert.same(res.data[1].workspace.id, workspace.id)
          assert.same(res.data[1].rbac_role.id, role.id)
        end)

        it("The endpoint should work with the 'offset' filter", function()
          local qty = 3
          
          for i = 1, qty do
            local _, _role, _workspace = insert_entities()
            -- insert mapping with one group
            insert_mapping(group, _role, _workspace)
          end

          local res_1 = get_request("/groups/" .. group.id .. "/roles?size=" .. qty-1)
          local res_2 = get_request(res_1.next)

          -- it's qty+1  since,
          -- there is 1 mapping created during the "before_each"
          assert.is_equal(qty + 1, #res_1.data + #res_2.data)
        end)

        it("The endpoint should cache entity correctly", function()
          local res_before, res_after
          local comment = "now we have comment"
          local new_name = "new_name"
          
          -- ensure entities states before update
          res_before = get_request("/groups/" .. group.id .. "/roles")
          assert.is_nil(res_before.data[1].group.comment)
          assert.not_same(new_name, res_before.data[1].rbac_role.name)

          -- update entities
          assert.res_status(200, assert(client:send {
            method = "PATCH",
            path = "/groups/" .. group.id,
            body = {
              comment = comment
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))

          assert.res_status(200, assert(client:send {
            method = "PATCH",
            path = "/rbac/roles/" .. role.id,
            body = {
              name = new_name
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))

          -- check entities states after update
          res_after = get_request("/groups/" .. group.id .. "/roles")
          assert.same(comment, res_after.data[1].group.comment)
          assert.same(new_name, res_after.data[1].rbac_role.name)
        end)
      end)
      
      describe("POST", function()
        it("The endpoint should not create a mapping with incorrect params", function()
          local _group, _role, _workspace = insert_entities()
          
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
              },
            }))
            assert.same("must provide the workspace_id", json_no_workspace)

            local json_no_role = assert.res_status(400, assert(client:send {
              method = "POST",
              path = "/groups/" .. _group.id .. "/roles",
              body = {
                workspace_id = _workspace.id,
              },
              headers = {
                ["Content-Type"] = "application/json",
              },
            }))
            assert.same("must provide the rbac_role_id", json_no_role)
          end

          do
            -- entities need to be found
            assert.res_status(404, assert(client:send {
              method = "POST",
              path = "/groups/" .. utils.uuid() .. "/roles",
              body = {
                rbac_role_id = _role.id,
                workspace_id = _workspace.id,
              },
              headers = {
                ["Content-Type"] = "application/json",
              },
            }))
  
            assert.res_status(404, assert(client:send {
              method = "POST",
              path = "/groups/" .. _group.id .. "/roles",
              body = {
                workspace_id = utils.uuid(),
                rbac_role_id = _role.id,
              },
              headers = {
                ["Content-Type"] = "application/json",
              },
            }))
  
            assert.res_status(404, assert(client:send {
              method = "POST",
              path = "/groups/" .. _group.id .. "/roles",
              body = {
                workspace_id = _workspace.id,
                rbac_role_id = utils.uuid(),
              },
              headers = {
                ["Content-Type"] = "application/json",
              },
            }))
          end
        end)

        it("The endpoint should create a mapping with correct params", function()
          local _group, _role, _workspace = insert_entities()

          local json = assert.res_status(201, assert(client:send {
            method = "POST",
            path = "/groups/" .. _group.id .. "/roles",
            body = {
              rbac_role_id = _role.id,
              workspace_id = _workspace.id,
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))
          
          local res = cjson.decode(json)

          assert.same(res.group.id, _group.id)
          assert.same(res.workspace.id, _workspace.id)
          assert.same(res.rbac_role.id, _role.id)
        end)
      end)

      describe("DELETE", function()
        before_each(function()
          group, role, workspace = insert_entities()
          insert_mapping(group, role, workspace)
        end)

        it("The endpoint should delete a mapping with correct params", function()
          assert.res_status(204, assert(client:send {
            method = "DELETE",
            path = "/groups/" .. group.id .. "/roles",
            body = {
              rbac_role_id = role.id,
              workspace_id = workspace.id,
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))

          local json = assert.res_status(200, assert(client:send {
            method = "GET",
            path = "/groups/" .. group.id .. "/roles",
          }))

          local res = cjson.decode(json)

          assert.same({}, res.data)
        end)
      end)
    end)
  end)
end
