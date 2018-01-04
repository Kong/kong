local typedefs = require "kong.db.schema.typedefs"


local function validate_name(name)
  if not string.match(name, "^[%w%.%-%_~]+$") then
    return nil,
           "invalid value '" .. name ..
           "': it must only contain alphanumeric and '., -, _, ~' characters"
  end

  return true
end


return {
  name = "services",
  primary_key = { "id" },

  fields = {
    { id              = typedefs.uuid, },
    { created_at      = { type = "integer", timestamp = true, auto = true }, },
    { updated_at      = { type = "integer", timestamp = true, auto = true }, },
    { name            = { type = "string", unique = true,
                          custom_validator = validate_name }, },
    { retries         = { type = "integer", default = 5, between = { 0, 32767 } }, },
    -- { tags          = { type = "array", array = { type = "string" } }, },
    { protocol        = typedefs.protocol { required = true, default = "http" } },
    { host            = typedefs.host { required = true } },
    { port            = typedefs.port { required = true, default = 80 }, },
    { path            = typedefs.path },
    { connect_timeout = typedefs.timeout { default = 60000 }, },
    { write_timeout   = typedefs.timeout { default = 60000 }, },
    { read_timeout    = typedefs.timeout { default = 60000 }, },
    -- { load_balancer = { type = "foreign", reference = "load_balancers" } },
  },
}
