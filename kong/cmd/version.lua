local ee_meta = require "kong.enterprise_edition.meta"

local lapp = [[
Usage: kong version [OPTIONS]

Print Kong's version. With the -a option, will print
the version of all underlying dependencies.

Options:
 -a,--all         get version of all dependencies
]]

local str = [[
Kong Enterprise: %s
ngx_lua: %s
nginx: %s
Lua: %s]]

local function execute(args)
  if args.all then
    print(string.format(str,
      tostring(ee_meta.versions.package),
      ngx.config.ngx_lua_version,
      ngx.config.nginx_version,
      jit and jit.version or _VERSION
    ))
  else
    print("Kong Enterprise " .. tostring(ee_meta.versions.package))
  end
end

return {
  lapp = lapp,
  execute = execute
}
