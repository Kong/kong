local typedefs = require "kong.db.schema.typedefs"


return {
  name = "file-log",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          { path = { description = "The file path of the output log file. The plugin creates the log file if it doesn't exist yet. Make sure Kong has write permissions to this file.", type = "string",
                     required = true,
                     match = [[^[^*&%%\`]+$]],
                     err = "not a valid filename",
          }, },
          { reopen = { description = "Determines whether the log file is closed and reopened on every request. If the file\nis not reopened, and has been removed/rotated, the plugin keeps writing to the\nstale file descriptor, and hence loses information.", type = "boolean", required = true, default = false }, },
          { custom_fields_by_lua = typedefs.lua_code },
        },
    }, },
  }
}
