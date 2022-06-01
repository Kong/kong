local pl_path = require "pl.path"
local typedefs = require "kong.db.schema.typedefs"

local DEFAULT_PREFIX = pl_path.join(kong.configuration.prefix, "logs/")
local prefix = kong.configuration.plugin_file_log_path_prefix or DEFAULT_PREFIX

if string.sub(prefix, -1) ~= "/" then
  prefix = prefix .. "/"
end

local path_pattern = string.format([[^%s[^*&%%\`]+$]], prefix)

local err_msg = 
  string.format("not a valid file name, "
              .. "or the prefix is not [%s], "
              .. "or contains `..`, "
              .. "you may need to check the configuration "
              .. "`plugin_file_log_path_prefix`",
                 prefix)


return {
  name = "file-log",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          { path = { type = "string",
                     required = true,
                     match = path_pattern,
                     -- to avoid the path traversal attack
                     not_match = [[%.%.]],
                     err = err_msg,
          }, },
          { reopen = { type = "boolean", required = true, default = false }, },
          { custom_fields_by_lua = typedefs.lua_code },
        },
    }, },
  }
}
