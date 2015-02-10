package = "kong"
version = "0.1-1"
supported_platforms = {"linux", "macosx"}
source = {
  url = "git://github.com/Mashape/kong",
  branch = "master"
}
description = {
  summary = "Kong, the fastest and most installed API layer in the universe",
  detailed = [[
    Kong is the most popular API layer in the world
    that provides API management and analytics for any kind
    of API.
  ]],
  homepage = "http://getkong.org",
  license = "MIT"
}
dependencies = {
  "lua ~> 5.1",

  "lsqlite3 ~> 0.9.1-2",
  "uuid ~> 0.2-1",
  "lapis ~> 1.1.0-1",
  "luasec ~> 0.5-2",
  "yaml ~> 1.1.1-1",
  "luaxml ~> 101012-1",
  "lrexlib-pcre ~> 2.7.2-1",
  "stringy ~> 0.2-1",
  "inspect ~> 3.0-1",

  "busted ~> 2.0.rc5-0",
  "luafilesystem ~> 1.6.2"
}
build = {
  type = "builtin",
  modules = {
    ["kong"] = "src/main.lua",
    ["classic"] = "src/classic.lua",
    ["cassandra"] = "src/cassandra.lua",

    ["kong.tools.utils"] = "src/kong/tools/utils.lua",
    ["kong.tools.faker"] = "src/kong/tools/faker.lua",
    ["kong.tools.migrations"] = "src/kong/tools/migrations.lua",

    ["kong.base_plugin"] = "src/kong/base_plugin.lua",

    ["kong.core.handler"] = "src/kong/core/handler.lua",
    ["kong.core.access"] = "src/kong/core/access.lua",
    ["kong.core.header_filter"] = "src/kong/core/header_filter.lua",

    ["kong.dao.schemas"] = "src/kong/dao/schemas.lua",

    ["kong.dao.cassandra.factory"] = "src/kong/dao/cassandra/factory.lua",
    ["kong.dao.cassandra.base_dao"] = "src/kong/dao/cassandra/base_dao.lua",
    ["kong.dao.cassandra.apis"] = "src/kong/dao/cassandra/apis.lua",
    ["kong.dao.cassandra.metrics"] = "src/kong/dao/cassandra/metrics.lua",
    ["kong.dao.cassandra.plugins"] = "src/kong/dao/cassandra/plugins.lua",
    ["kong.dao.cassandra.accounts"] = "src/kong/dao/cassandra/accounts.lua",
    ["kong.dao.cassandra.applications"] = "src/kong/dao/cassandra/applications.lua",

    ["kong.plugins.authentication.handler"] = "src/kong/plugins/authentication/handler.lua",
    ["kong.plugins.authentication.access"] = "src/kong/plugins/authentication/access.lua",
    ["kong.plugins.authentication.schema"] = "src/kong/plugins/authentication/schema.lua",

    ["kong.plugins.networklog.handler"] = "src/kong/plugins/networklog/handler.lua",
    ["kong.plugins.networklog.log"] = "src/kong/plugins/networklog/log.lua",
    ["kong.plugins.networklog.schema"] = "src/kong/plugins/networklog/schema.lua",

    ["kong.plugins.ratelimiting.handler"] = "src/kong/plugins/ratelimiting/handler.lua",
    ["kong.plugins.ratelimiting.access"] = "src/kong/plugins/ratelimiting/access.lua",
    ["kong.plugins.ratelimiting.schema"] = "src/kong/plugins/ratelimiting/schema.lua",

    ["kong.web.app"] = "src/kong/web/app.lua",
    ["kong.web.routes.accounts"] = "src/kong/web/routes/accounts.lua",
    ["kong.web.routes.apis"] = "src/kong/web/routes/apis.lua",
    ["kong.web.routes.applications"] = "src/kong/web/routes/applications.lua",
    ["kong.web.routes.plugins"] = "src/kong/web/routes/plugins.lua",
    ["kong.web.routes.base_controller"] = "src/kong/web/routes/base_controller.lua"
  },
  copy_directories = { "src/kong/web/admin", "src/kong/web/static" },
  install = {
    bin = { "bin/kong" }
  }
}
