package = "Apenode"
version = "0.1-1"
source = {
   url = "https://github.com/Mashape/lua-resty-apenode"
}
description = {
   summary = "The Apenode, ",
   detailed = [[
      This is an example for the LuaRocks tutorial.
      Here we would put a detailed, typically
      paragraph-long description.
   ]],
   homepage = "http://...", -- We don't have one yet
   license = "MIT/X11" -- or whatever you like
}
dependencies = {
   "lua ~> 5.1",
   "inspect >= 3.0-1"
}
build = {
   type = "make"
}
