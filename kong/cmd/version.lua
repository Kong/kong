-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
