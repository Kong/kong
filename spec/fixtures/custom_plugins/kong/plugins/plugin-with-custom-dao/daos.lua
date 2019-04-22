local typedefs = require "kong.db.schema.typedefs"

return {
  custom_dao = {
    dao = "kong.plugins.plugin-with-custom-dao.custom_dao",
    name = "custom_dao",
    primary_key = { "id" },
    fields = {
      { id = typedefs.uuid },
    },
  },
}
