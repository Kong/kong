package = "Apenode"
version = "0.1-1"
source = {
   url = "git://github.com/Mashape/lua-resty-apenode",
   tag = "master"
}
description = {
   summary = "Apenode, the fastest and most installed API layer in the universe",
   detailed = [[
      The Apenode is the most popular API layer in the world
      that provides API management and analytics for any kind
      of API.
   ]],
   homepage = "http://apenode.com",
   license = "MIT"
}
dependencies = {
   "lua ~> 5.1",
   "luasec ~> 0.5-2",
   "uuid ~> 0.2-1",
   "yaml ~> 1.1.1-1",
   "lapis ~> 1.0.6-1",
   "inspect ~> 3.0-1"
}
build = {
   type = "make"
}
