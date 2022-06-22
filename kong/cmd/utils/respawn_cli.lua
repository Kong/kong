local pl_path = require "pl.path"
local prefix_handler = require "kong.cmd.utils.prefix_handler"

return function(conf)   
  if not os.getenv("KONG_CLI_RESPAWNED") then
    -- initial run, so go update the environment
    local script = {}
    -- add cli recursion detection
    table.insert(script, "export KONG_CLI_RESPAWNED=1")

    local combined = pl_path.join(ngx.config.prefix(), "lua_ssl_trusted_combined.crt")
    prefix_handler.gen_trusted_certs_combined_file(combined, conf.lua_ssl_trusted_certificate)

    -- rebuild the invoked commandline, while inserting extra resty-flags
    local cmd = { "exec" }
    for i = -1, #arg do
      table.insert(cmd, "'" .. arg[i] .. "'")
    end

    table.insert(cmd, 3, "--http-conf 'lua_ssl_trusted_certificate " .. combined .. ";'")

    table.insert(script, table.concat(cmd, " "))

    -- recurse cli command, with proper variables (un)set for clean testing
    local _, _, rc = os.execute(table.concat(script, "; "))
    os.exit(rc)
  end
end