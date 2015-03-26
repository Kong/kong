package = "kong"
version = "0.1.0beta-2"
supported_platforms = {"linux", "macosx"}
source = {
  url = "git://github.com/Mashape/kong",
  tag = "0.1.0beta-2"
}
description = {
  summary = "Kong is a scalable and customizable API Management Layer built on top of Nginx.",
  homepage = "http://getkong.org",
  license = "MIT"
}
dependencies = {
  "lua ~> 5.1",

  "uuid ~> 0.2-1",
  "luatz ~> 0.3-1",
  "yaml ~> 1.1.1-1",
  "luasec ~> 0.5-2",
  "lapis ~> 1.1.0-1",
  "inspect ~> 3.0-1",
  "stringy ~> 0.2-1",
  "cassandra ~> 0.5-4",
  "lua-path ~> 0.2.3-1",
  "lua-cjson ~> 2.1.0-1",
  "luasocket ~> 2.0.2-5",
  "ansicolors ~> 1.0.2-3",
  "lrexlib-pcre ~> 2.7.2-1",
  "lua-llthreads2 ~> 0.1.3-1"
}
build = {
  type = "builtin",
  modules = {
    ["kong"] = "src/kong.lua",

    ["classic"] = "src/vendor/classic.lua",
    ["lapp"] = "src/vendor/lapp.lua",

    ["kong.constants"] = "src/constants.lua",

    ["kong.cli.utils"] = "src/cli/utils/utils.lua",
    ["kong.cli.utils.start"] = "src/cli/utils/start.lua",
    ["kong.cli.utils.stop"] = "src/cli/utils/stop.lua",
    ["kong.cli.db"] = "src/cli/db.lua",
    ["kong.cli.config"] = "src/cli/config.lua",
    ["kong.cli.stop"] = "src/cli/stop.lua",
    ["kong.cli.start"] = "src/cli/start.lua",
    ["kong.cli.restart"] = "src/cli/restart.lua",
    ["kong.cli.version"] = "src/cli/version.lua",

    ["kong.tools.utils"] = "src/tools/utils.lua",
    ["kong.tools.io"] = "src/tools/io.lua",
    ["kong.tools.migrations"] = "src/tools/migrations.lua",
    ["kong.tools.faker"] = "src/tools/faker.lua",
    ["kong.tools.cache"] = "src/tools/cache.lua",
    ["kong.tools.timestamp"] = "src/tools/timestamp.lua",
    ["kong.tools.http_client"] = "src/tools/http_client.lua",

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
    ["kong.dao.cassandra.consumers"] = "src/dao/cassandra/consumers.lua",
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
    ["kong.web.routes.consumers"] = "src/web/routes/consumers.lua",
    ["kong.web.routes.applications"] = "src/web/routes/applications.lua",
    ["kong.web.routes.plugins"] = "src/web/routes/plugins.lua",
    ["kong.web.routes.base_controller"] = "src/web/routes/base_controller.lua"
  },
  install = {
    conf = { "kong.yml" },
    bin = { "bin/kong" }
  },
  copy_directories = { "src/web/admin/", "src/web/static/", "database/migrations/" }
}
