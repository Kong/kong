package = "apenode"
version = "0.1-1"
supported_platforms = {"linux", "macosx"}
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

  "lsqlite3 ~> 0.9.1-2",
  "cassandra ~> 0.3-1",
  "uuid ~> 0.2-1",
  "lapis ~> 1.0.6-1",
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
    ["apenode"] = "src/main.lua",
    ["classic"] = "src/classic.lua",

    ["apenode.tools.utils"] = "src/apenode/tools/utils.lua",
    ["apenode.tools.faker"] = "src/apenode/tools/faker.lua",
    ["apenode.tools.migrations"] = "src/apenode/tools/migrations.lua",

    ["apenode.base_plugin"] = "src/apenode/base_plugin.lua",

    ["apenode.core.handler"] = "src/apenode/core/handler.lua",
    ["apenode.core.access"] = "src/apenode/core/access.lua",
    ["apenode.core.header_filter"] = "src/apenode/core/header_filter.lua",

    ["apenode.dao.schemas"] = "src/apenode/dao/schemas.lua",

    ["apenode.dao.cassandra.factory"] = "src/apenode/dao/cassandra/factory.lua",
    ["apenode.dao.cassandra.base_dao"] = "src/apenode/dao/cassandra/base_dao.lua",
    ["apenode.dao.cassandra.apis"] = "src/apenode/dao/cassandra/apis.lua",
    ["apenode.dao.cassandra.metrics"] = "src/apenode/dao/cassandra/metrics.lua",
    ["apenode.dao.cassandra.plugins"] = "src/apenode/dao/cassandra/plugins.lua",
    ["apenode.dao.cassandra.accounts"] = "src/apenode/dao/cassandra/accounts.lua",
    ["apenode.dao.cassandra.applications"] = "src/apenode/dao/cassandra/applications.lua",

    ["apenode.models.base_model"] = "src/apenode/models/base_model.lua",
    ["apenode.models.account"] = "src/apenode/models/account.lua",
    ["apenode.models.api"] = "src/apenode/models/api.lua",
    ["apenode.models.application"] = "src/apenode/models/application.lua",
    ["apenode.models.metric"] = "src/apenode/models/metric.lua",
    ["apenode.models.plugin"] = "src/apenode/models/plugin.lua",

    ["apenode.plugins.authentication.handler"] = "src/apenode/plugins/authentication/handler.lua",
    ["apenode.plugins.authentication.access"] = "src/apenode/plugins/authentication/access.lua",

    ["apenode.plugins.networklog.handler"] = "src/apenode/plugins/networklog/handler.lua",
    ["apenode.plugins.networklog.log"] = "src/apenode/plugins/networklog/log.lua",

    ["apenode.plugins.ratelimiting.handler"] = "src/apenode/plugins/ratelimiting/handler.lua",
    ["apenode.plugins.ratelimiting.access"] = "src/apenode/plugins/ratelimiting/access.lua",

    ["apenode.web.app"] = "src/apenode/web/app.lua",
    ["apenode.web.routes.accounts"] = "src/apenode/web/routes/accounts.lua",
    ["apenode.web.routes.apis"] = "src/apenode/web/routes/apis.lua",
    ["apenode.web.routes.applications"] = "src/apenode/web/routes/applications.lua",
    ["apenode.web.routes.plugins"] = "src/apenode/web/routes/plugins.lua",
    ["apenode.web.routes.base_controller"] = "src/apenode/web/routes/base_controller.lua"
  },
  copy_directories = { "src/apenode/web/admin", "src/apenode/web/static" },
  install = {
    bin = { "bin/apenode" }
  }
}
