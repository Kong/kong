local iputils = require "resty.iputils"


local function validate_ip(ip)
  local _, err = iputils.parse_cidr(ip)
  -- It's an error only if the second variable is a string
  if type(err) == "string" then
    return false, "cannot parse '" .. ip .. "': " .. err
  end
  return true
end


local ip = { type = "string", custom_validator = validate_ip }


return {
  name = "ip-restriction",
  fields = {
    { config = {
        type = "record",
        fields = {
          { whitelist = { type = "array", elements = ip, }, },
          { blacklist = { type = "array", elements = ip, }, },
        },
      },
    },
  },
  entity_checks = {
    { only_one_of = { "config.whitelist", "config.blacklist" }, },
    { at_least_one_of = { "config.whitelist", "config.blacklist" }, },
  },
}
