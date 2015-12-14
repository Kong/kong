-- config file for the debug tools
local config = {
  
  -- path to ZeroBrane studio, including the trailing slash
  zerobrane_path = "/opt/zbstudio/",
  
  -- options to pass to Busted
  test_options = "--verbose --output spec/busted-print.lua",
  
  -- LuaPath for Kong (default from the Kong config .yml files
  kong_path = "./kong/?.lua;;",
}

--------------------------------
-- nothing to customize below --
--------------------------------

config.lpath = config.zerobrane_path..'lualibs/?/?.lua;'..config.zerobrane_path..'lualibs/?.lua;'..config.kong_path

-- some system detection for the c-libs path
local cpath
if io.popen("uname -s"):read("*l") == "Darwin" then
  -- we have a Mac
  cpath = "bin/clibs/?.dylib;;"
else
  -- assuming linux here
  if io.popen("uname -m"):read("*l") == "x86_64" then
    -- 64bit unix
    cpath = "bin/linux/x64/clibs/?.so;;"
  else
    -- 32bit unix
    cpath = "bin/linux/x86/clibs/?.so;;"
  end
end

config.cpath = config.zerobrane_path .. cpath


return config
  