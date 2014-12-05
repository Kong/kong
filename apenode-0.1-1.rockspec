package = "apenode"
version = "0.1-1"
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
  "busted ~> 2.0.rc3-0",
  "stringy ~> 0.2-1"
}
build = {
  type = "builtin",
  modules = {
    ["apenode"] = "src/main.lua",
    ["apenode.constants"] = "src/apenode/constants.lua",
    ["apenode.utils"] = "src/apenode/utils.lua",

    ["apenode.core"] = "src/apenode/core/handler.lua",
    ["apenode.core.access"] = "src/apenode/core/access.lua",
    ["apenode.core.header_filter"] = "src/apenode/core/header_filter.lua",

    ["apenode.dao.json.apis"] = "src/apenode/dao/json/apis.lua",
    ["apenode.dao.json.applications"] = "src/apenode/dao/json/applications.lua",
    ["apenode.dao.json.base_dao"] = "src/apenode/dao/json/base_dao.lua",
    ["apenode.dao.json.factory"] = "src/apenode/dao/json/factory.lua",
    ["apenode.dao.json.file_table"] = "src/apenode/dao/json/file_table.lua",
    ["apenode.dao.json.metrics"] = "src/apenode/dao/json/metrics.lua",

    ["apenode.plugins.authentication"] = "src/apenode/plugins/authentication/handler.lua",
    ["apenode.plugins.authentication.access"] = "src/apenode/plugins/authentication/access.lua",

    ["apenode.plugins.networklog"] = "src/apenode/plugins/networklog/handler.lua",
    ["apenode.plugins.networklog.log"] = "src/apenode/plugins/networklog/log.lua",

    ["apenode.plugins.transformations"] = "src/apenode/plugins/transformations/handler.lua",
    ["apenode.plugins.transformations.body_filter"] = "src/apenode/plugins/transformations/body_filter.lua",
    ["apenode.plugins.transformations.header_filter"] = "src/apenode/plugins/transformations/header_filter.lua",

    ["apenode.web.app"] = "src/apenode/web/app.lua",
    ["apenode.web.apis"] = "src/apenode/web/apis.lua",
    ["apenode.web.applications"] = "src/apenode/web/applications.lua",
    ["apenode.web.base_controller"] = "src/apenode/web/base_controller.lua"
  },
  copy_directories = { "src/apenode/web/admin", "src/apenode/web/static" },
  install = {
    bin = { "bin/apenode" }
  }
}
