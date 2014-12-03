package = "apenode"
version = "0.0-1"
source = {
   url = "git://github.com/Mashape/lua-resty-apenode",
   branch = "master"
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
   "inspect ~> 3.0-1",
   "luaxml ~> 101012-1",
   "busted ~> 2.0.rc3-0"
}
build = {
   type = "builtin",
   modules = {
      ["apenode"] = "src/main.lua",
      ["apenode.core.access"] = "src/core/access.lua",
      ["apenode.core.handler"] = "src/core/handler.lua",
      ["apenode.core.handler_filter"] = "src/core/header_filter.lua",
      ["apenode.core.log"] = "src/core/log.lua",
      ["apenode.core.utils"] = "src/core/utils.lua",

      ["apenode.web.app"] = "src/web/app.lua",

      ["apenode.dao.memory"] = "src/dao/memory/factory.lua",
      ["apenode.dao.memory.api"] = "src/dao/memory/api.lua",
      ["apenode.dao.memory.application"] = "src/dao/memory/application.lua",

      ["apenode.plugins.transformations.handler"] = "src/plugins/transformations/handler.lua",
      ["apenode.plugins.transformations.header_filter"] = "src/plugins/transformations/header_filter.lua",
      ["apenode.plugins.transformations.body_filter"] = "src/plugins/transformations/body_filter.lua"
   }
}
