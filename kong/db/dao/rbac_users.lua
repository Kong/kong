local constants = require "kong.constants"
local typedefs = require "kong.db.schema.typedefs"
local utils = require "kong.tools.utils"
local Entity = require "kong.db.schema.entity"
local db = require "kong.db"
local MetaSchema = require "kong.db.schema.metaschema"
local wokspaces = require "kong.workspaces"
local rbac = require "kong.rbac"

return {
  get_roles = function(self, db, user)
    return rbac.entity_relationships(db, user,
      "user", "role", "rbac_user_roles")
  end
}
