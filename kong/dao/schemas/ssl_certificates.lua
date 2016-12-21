local singletons = require "kong.singletons"


return {
  table = "ssl_certificates",
  primary_key = { "id" },
  fields = {
    id = { type = "id", dao_insert_value = true, required = true },
    cert = { type = "string", required = true },
    key = { type = "string", required = true },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
  },
  marshall_event = function(schema, t)
    local rows, err = singletons.dao.ssl_servers_names:find_all {
      ssl_certificate_id = t.id
    }
    if err then
      ngx.log(ngx.ERR, "could not fetch server names for cluster event: ", err)
      return
    end

    local entity = {
      id = t.id,
      snis = {}
    }

    for i = 1, #rows do
      table.insert(entity.snis, rows[i].name)
    end

    return entity
  end,
}
