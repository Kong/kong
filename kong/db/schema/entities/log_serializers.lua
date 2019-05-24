local typedefs = require "kong.db.schema.typedefs"

return {
  name = "log_serializers",
  primary_key = { "id" },
  endpoint_key = "name",

  fields = {
    { id = typedefs.uuid, },
    { name = { type = "string", required = true, unique = true }, },
    { chunk = { type = "string", required = true }, },
    { tags = typedefs.tags },
  },

  entity_checks = {
    { custom_entity_check = {
      field_sources = { "chunk" },
      fn = function(entity)
        local chunk = ngx.decode_base64(entity.chunk)
        if not chunk then
          return false, "could not decode serializer chunk"
        end

        local s = loadstring(chunk)
        if not s then
          return nil, "could not load serializer chunk"
        end

        if type(s().serialize) ~= "function" then
          return nil, "loaded serializer does not contain a public 'serialize' function"
        end

        return true
      end,
    } }
  }
}
