package = "kong"
version = "0.0.1beta-1"
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

  "uuid ~> 0.2-1",
  "lapis ~> 1.1.0-1",
  "luasec ~> 0.5-2",
  "yaml ~> 1.1.1-1",
  "luaxml ~> 101012-1",
  "cassandra ~> 0.5-4",
  "lrexlib-pcre ~> 2.7.2-1",
  "stringy ~> 0.2-1",
  "inspect ~> 3.0-1",
  "luasocket ~> 2.0.2-5",
  "lua-llthreads2 ~> 0.1.3-1",
  "ansicolors ~> 1.0.2-3",
  "lua_cliargs ~> 2.3-3",
  "lua-path ~> 0.2.3-1",
  "luatz ~> 0.3-1"
}
build = {
  type = "builtin",
  modules = {
    ["kong"] = "src/kong.lua",

    ["classic"] = "src/vendor/classic.lua",
    ["lapp"] = "src/vendor/lapp.lua",

    ["kong.constants"] = "src/constants.lua",

    ["kong.cmd.utils"] = "src/cmd/utils.lua",
    ["kong.cmd.start"] = "src/cmd/start.lua",
    ["kong.cmd.stop"] = "src/cmd/stop.lua",
    ["kong.cmd.config"] = "src/cmd/config.lua",
    ["kong.cmd.version"] = "src/cmd/version.lua",

    ["kong.tools.utils"] = "src/tools/utils.lua",
    ["kong.tools.timestamp"] = "src/tools/timestamp.lua",
    ["kong.tools.cache"] = "src/tools/cache.lua",
    ["kong.tools.http_client"] = "src/tools/http_client.lua",
    ["kong.tools.faker"] = "src/tools/faker.lua",
    ["kong.tools.migrations"] = "src/tools/migrations.lua",

    ["kong.resolver.handler"] = "src/resolver/handler.lua",
    ["kong.resolver.access"] = "src/resolver/access.lua",
    ["kong.resolver.header_filter"] = "src/resolver/header_filter.lua",

    ["kong.dao.error"] = "src/dao/error.lua",
    ["kong.dao.schemas"] = "src/dao/schemas.lua",
    ["kong.dao.cassandra.factory"] = "src/dao/cassandra/factory.lua",
    ["kong.dao.cassandra.base_dao"] = "src/dao/cassandra/base_dao.lua",
    ["kong.dao.cassandra.apis"] = "src/dao/cassandra/apis.lua",
    ["kong.dao.cassandra.metrics"] = "src/dao/cassandra/metrics.lua",
    ["kong.dao.cassandra.plugins"] = "src/dao/cassandra/plugins.lua",
    ["kong.dao.cassandra.accounts"] = "src/dao/cassandra/accounts.lua",
    ["kong.dao.cassandra.applications"] = "src/dao/cassandra/applications.lua",

    ["kong.plugins.base_plugin"] = "src/plugins/base_plugin.lua",

    ["kong.plugins.basicauth.handler"] = "src/plugins/basicauth/handler.lua",
    ["kong.plugins.basicauth.access"] = "src/plugins/basicauth/access.lua",
    ["kong.plugins.basicauth.schema"] = "src/plugins/basicauth/schema.lua",

    ["kong.plugins.queryauth.handler"] = "src/plugins/queryauth/handler.lua",
    ["kong.plugins.queryauth.access"] = "src/plugins/queryauth/access.lua",
    ["kong.plugins.queryauth.schema"] = "src/plugins/queryauth/schema.lua",

    ["kong.plugins.headerauth.handler"] = "src/plugins/headerauth/handler.lua",
    ["kong.plugins.headerauth.access"] = "src/plugins/headerauth/access.lua",
    ["kong.plugins.headerauth.schema"] = "src/plugins/headerauth/schema.lua",

    ["kong.plugins.tcplog.handler"] = "src/plugins/tcplog/handler.lua",
    ["kong.plugins.tcplog.log"] = "src/plugins/tcplog/log.lua",
    ["kong.plugins.tcplog.schema"] = "src/plugins/tcplog/schema.lua",

    ["kong.plugins.udplog.handler"] = "src/plugins/udplog/handler.lua",
    ["kong.plugins.udplog.log"] = "src/plugins/udplog/log.lua",
    ["kong.plugins.udplog.schema"] = "src/plugins/udplog/schema.lua",

    ["kong.plugins.filelog.handler"] = "src/plugins/filelog/handler.lua",
    ["kong.plugins.filelog.log"] = "src/plugins/filelog/log.lua",
    ["kong.plugins.filelog.schema"] = "src/plugins/filelog/schema.lua",

    ["kong.plugins.ratelimiting.handler"] = "src/plugins/ratelimiting/handler.lua",
    ["kong.plugins.ratelimiting.access"] = "src/plugins/ratelimiting/access.lua",
    ["kong.plugins.ratelimiting.schema"] = "src/plugins/ratelimiting/schema.lua",

    ["kong.web.app"] = "src/web/app.lua",
    ["kong.web.routes.apis"] = "src/web/routes/apis.lua",
    ["kong.web.routes.accounts"] = "src/web/routes/accounts.lua",
    ["kong.web.routes.applications"] = "src/web/routes/applications.lua",
    ["kong.web.routes.plugins"] = "src/web/routes/plugins.lua",
    ["kong.web.routes.base_controller"] = "src/web/routes/base_controller.lua"
  },
  install = {
    conf = { "kong.yml" },
    bin = { "bin/kong" }
  },
  copy_directories = { "src/web/admin", "src/web/static" }
}
