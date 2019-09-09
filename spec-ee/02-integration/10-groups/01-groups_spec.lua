local helpers	= require "spec.helpers"
local cjson 	= require "cjson"
local utils 	= require "kong.tools.utils"

local client
local db

local function run_kong(cmd, env)
	env = env or {}
	env.database = "postgres"
	env.plugins = env.plugins or "off"

	local cmdline = cmd .. " -c " .. helpers.test_conf_path
	local _, code, stdout, stderr = helpers.kong_exec(cmdline, env, true)
	return code, stdout, stderr
end

local function compare_all_field(src, expected)
	for k, t in pairs(src) do
		for k_2, v in pairs(t) do
			assert.is_equal(v, expected[k][k_2])
		end
	end
end

for _, strategy in helpers.each_strategy() do
	describe("Groups Entity #" .. strategy, function()
		lazy_setup(function()
			if strategy == "postgres" then
				assert(run_kong('migrations reset --yes'))
				assert(run_kong('migrations bootstrap'))
			end

			_, db = helpers.get_db_utils(strategy)
		end)

    lazy_teardown(function()
			helpers.stop_kong()
			if client then
				client:close()
			end
		end)
		
		describe("#Schema and Migration", function()
			lazy_setup(function()
				helpers.stop_kong()

				assert(helpers.start_kong({
					database  = strategy,
					smtp_mock = true,
				}))

				client = assert(helpers.admin_client())
				
				assert(db.groups)
				assert(db.group_rbac_roles)
			end)
			
			lazy_teardown(function()
        if client then
          client:close()
        end
			end)
			
			it("the groups schema in Lua should be init correctly", function()
				local expected_schema = {
					{
						id = {
							type = "string",
							uuid = true,
							auto = true
						}
					},
					{
						created_at = {
							timestamp = true,
							type = "integer",
							auto = true
						}
					},
					{
						name = {
							unique = true,
							required = true,
							type = "string"
						}
					},
					{
						comment = {
							type = "string"
						}
					},
					comment = {
						type = "string"
					},
					created_at = {
						timestamp = true,
						type = "integer",
						auto = true
					},
					name = {
						unique = true,
						required = true,
						type = "string"
					},
					id = {
						type = "string",
						uuid = true,
						auto = true
					}
				}

				local res = assert(client:send {
					method = "GET",
					path = "/schemas/groups"
				})

				local json = assert.res_status(200, res)
				local schema = assert(cjson.decode(json).fields)

				for i, v in pairs(schema) do
					compare_all_field(v, expected_schema[i])
				end
			end)

			it("The group_rbac_roles schema in Lua should be init correctly", function()
				local expected_schema = {
					{
						created_at = {
							timestamp = true,
							type = "integer",
							auto = true
						}
					},
					{
						group = {
							type = "foreign",
							required = true,
							reference = "groups",
							on_delete = "cascade"
						}
					},
					{
						rbac_role = {
							type = "foreign",
							required = true,
							reference = "rbac_roles",
							on_delete = "cascade"
						}
					},
					{
						workspace = {
							type = "foreign",
							required = true,
							reference = "workspaces",
							on_delete = "cascade"
						}
					}
				}

				local res = assert(client:send {
					method = "GET",
					path = "/schemas/group_rbac_roles"
				})

				local json = assert.res_status(200, res)
				local schema = assert(cjson.decode(json).fields)
				
				for i, v in pairs(schema) do
					compare_all_field(v, expected_schema[i])
				end
			end)

			it("A group 'name' should be required during creation", function()
				local _, _, err_t = db.groups:insert({
					comment = "adding group without name<externalId>"
				})
				
				assert.same("schema violation", err_t.name)
				assert(err_t.fields.name)
			end)

			it("'Comment' is optional during creation", function()
				local res_insert = assert(db.groups:insert({
					name = "test_group_identity"
				}))

				local res_select = assert(db.groups:select({
					id = res_insert.id
				}))

				assert.same(res_insert, res_select)
			end)

			it("Default creation with 'name' and 'comment'", function()
				local submission = {
					name = "test_group_identity" .. utils.uuid(),
					comment = "test comment string for group entity"
				}

				local res_insert = assert(db.groups:insert(submission))

				assert.same(submission.name, res_insert.name)
				assert.same(submission.comment, res_insert.comment)
			end)

			it("The 'name' should be unique", function()
				local submission = { name = "test_group_identity" .. utils.uuid() }
				
				assert(db.groups:insert(submission))

				local _, _, err_t = db.groups:insert(submission)

				assert.same("unique constraint violation", err_t.name)
			end)
		end)

		describe("Delete cascade should works as expected", function()
			local group, role, workspace

			local function insert_and_delete(dao_name, delete_id)
				local mapping = {
					rbac_role = { id = role.id },
					workspace = { id = workspace.id },
					group 	  = { id = group.id }
				}

				assert(db.group_rbac_roles:insert(mapping))
				assert(db[dao_name]:delete({ id = delete_id }))
					
				mapping.workspace = nil
					
				assert.is_nil(db.group_rbac_roles:select(mapping))
			end

			lazy_setup(function()
				helpers.stop_kong()

				assert(helpers.start_kong({
					database  = strategy,
					smtp_mock = true,
				}))

				client = assert(helpers.admin_client())
				
				assert(db.groups)
				assert(db.group_rbac_roles)
			end)
			
			lazy_teardown(function()
        if client then
          client:close()
        end
			end)

			before_each(function()
				group = assert(db.groups:insert{ name = "test_group_" .. utils.uuid()})
				role = assert(db.rbac_roles:insert{ name = "test_role_" .. utils.uuid()})
				workspace = assert(db.workspaces:insert{ name = "test_workspace_" .. utils.uuid()})
			end)

			it("Mapping should be removed after referenced group has been removed", function()
					insert_and_delete("groups", group.id)
			end)

			it("Mapping should be removed after referenced rbac_role has been removed", function()
				insert_and_delete("rbac_roles", role.id)
			end)

			it("Mapping should be removed after referenced workspace has been removed", function()
				insert_and_delete("workspaces", workspace.id)
			end)
		end)
	end)
end
