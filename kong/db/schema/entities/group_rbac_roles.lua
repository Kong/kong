local typedefs = require "kong.db.schema.typedefs"

return {
	name 				= "group_rbac_roles",
	generate_admin_api  = false,
	primary_key 		= { "group", "rbac_role" },
	fields = {
		{ created_at     = typedefs.auto_timestamp_s },
		{ group = { type = "foreign", required = true, reference = "groups", on_delete = "cascade" } },
		{ rbac_role = { type = "foreign", required = true, reference = "rbac_roles", on_delete = "cascade" } },
		{ workspace = { type = "foreign", required = true, reference = "workspaces", on_delete = "cascade" } },
	},
}
