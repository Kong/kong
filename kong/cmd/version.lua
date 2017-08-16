local meta = require "kong.meta"

local lapp = [[
Usage: kong version [OPTIONS]

Print Kong's version. With the -a option, will print
the version of all underlying dependencies.

Options:
 -a,--all         get version of all dependencies
]]

local str = [[
Kong: %s
ngx_lua: %s
nginx: %s
Lua: %s]]

local function execute(args)
  if args.all then
    print(string.format(str,
      meta._VERSION,
      ngx.config.ngx_lua_version,
      ngx.config.nginx_version,
      jit and jit.version or _VERSION
    ))
  else
    print(meta._VERSION)
  end
end

return {
  lapp = lapp,
  execute = execute
}
