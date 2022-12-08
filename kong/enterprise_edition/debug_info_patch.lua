-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Enterprise plugins are byte-compiled in the /tmp/build directory,
-- which causes them to contain debug information prefixed with
-- /tmp/build/usr/local, even though the resulting files are living in
-- /usr/local at runtime.  This is an issue because the debug
-- information is used by e.g. the datafile library to locate
-- additional resources included in a luarock.  To solve this problem,
-- we're wrapping `debug.getinfo` in a function that removes the
-- /tmp/build prefix from the paths returned.

do
  local real_getinfo = debug.getinfo
  -- luacheck: ignore 122
  debug.getinfo = function(arg, flags)
    if type(arg) == "number" then
      local info = real_getinfo(arg + 1, flags)
      if info and info.source then
        info.source = info.source:gsub("@/tmp/build", "@")
      end
      return info
    else
      return real_getinfo(arg, flags)
    end
  end
end
