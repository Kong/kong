package = "kong"
version = "0.3.0-1"
supported_platforms = {"linux", "macosx"}
source = {
  url = "git://github.com/Mashape/kong",
  tag = "0.3.0"
}
description = {
  summary = "Kong is a scalable and customizable API Management Layer built on top of Nginx.",
  homepage = "http://getkong.org",
  license = "MIT"
}
dependencies = {
  "lua ~> 5.1",
  "luasec ~> 0.5-2",

  "uuid ~> 0.2-1",
  "luatz ~> 0.3-1",
  "yaml ~> 1.1.1-1",
  "lapis ~> 1.1.0-1",
  "stringy ~> 0.4-1",
  "cassandra ~> 0.5-7",
  "multipart ~> 0.1-3",
  "lua-path ~> 0.2.3-1",
  "lua-cjson ~> 2.1.0-1",
  "ansicolors ~> 1.0.2-3",
  "lbase64 ~> 20120820-1",

  "luasocket ~> 2.0.2-5",
  "lrexlib-pcre ~> 2.7.2-1",
  "lua-llthreads2 ~> 0.1.3-1"
}
build = {
  type = "builtin",
  modules = {
    ["kong"] = "kong/kong.lua",

    ["classic"] = "kong/vendor/classic.lua",
    ["lapp"] = "kong/vendor/lapp.lua",

    ["kong.constants"] = "kong/constants.lua",

    ["kong.cli.utils"] = "kong/cli/utils/utils.lua",
    ["kong.cli.utils.signal"] = "kong/cli/utils/signal.lua",
    ["kong.cli.db"] = "kong/cli/db.lua",
    ["kong.cli.config"] = "kong/cli/config.lua",
    ["kong.cli.quit"] = "kong/cli/quit.lua",
    ["kong.cli.stop"] = "kong/cli/stop.lua",
    ["kong.cli.start"] = "kong/cli/start.lua",
    ["kong.cli.reload"] = "kong/cli/reload.lua",
    ["kong.cli.restart"] = "kong/cli/restart.lua",
    ["kong.cli.version"] = "kong/cli/version.lua",
    ["kong.cli.migrations"] = "kong/cli/migrations.lua",

    ["kong.tools.io"] = "kong/tools/io.lua",
    ["kong.tools.utils"] = "kong/tools/utils.lua",
    ["kong.tools.faker"] = "kong/tools/faker.lua",
    ["kong.tools.syslog"] = "kong/tools/syslog.lua",
    ["kong.tools.ngx_stub"] = "kong/tools/ngx_stub.lua",
    ["kong.tools.printable"] = "kong/tools/printable.lua",
    ["kong.tools.responses"] = "kong/tools/responses.lua",
    ["kong.tools.timestamp"] = "kong/tools/timestamp.lua",
    ["kong.tools.migrations"] = "kong/tools/migrations.lua",
    ["kong.tools.http_client"] = "kong/tools/http_client.lua",
    ["kong.tools.database_cache"] = "kong/tools/database_cache.lua",

    ["kong.resolver.handler"] = "kong/resolver/handler.lua",
    ["kong.resolver.access"] = "kong/resolver/access.lua",
    ["kong.resolver.header_filter"] = "kong/resolver/header_filter.lua",
    ["kong.resolver.certificate"] = "kong/resolver/certificate.lua",
    ["kong.resolver.resolver_util"] = "kong/resolver/resolver_util.lua",

    ["kong.dao.error"] = "kong/dao/error.lua",
    ["kong.dao.schemas"] = "kong/dao/schemas.lua",
    ["kong.dao.cassandra.factory"] = "kong/dao/cassandra/factory.lua",
    ["kong.dao.cassandra.base_dao"] = "kong/dao/cassandra/base_dao.lua",
    ["kong.dao.cassandra.apis"] = "kong/dao/cassandra/apis.lua",
    ["kong.dao.cassandra.consumers"] = "kong/dao/cassandra/consumers.lua",
    ["kong.dao.cassandra.plugins_configurations"] = "kong/dao/cassandra/plugins_configurations.lua",
    ["kong.dao.cassandra.migrations"] = "kong/dao/cassandra/migrations.lua",
    ["kong.dao.cassandra.ratelimiting_metrics"] = "kong/dao/cassandra/ratelimiting_metrics.lua",
    ["kong.dao.cassandra.basicauth_credentials"] = "kong/dao/cassandra/basicauth_credentials.lua",
    ["kong.dao.cassandra.keyauth_credentials"] = "kong/dao/cassandra/keyauth_credentials.lua",

    ["kong.plugins.base_plugin"] = "kong/plugins/base_plugin.lua",

    ["kong.plugins.basicauth.handler"] = "kong/plugins/basicauth/handler.lua",
    ["kong.plugins.basicauth.access"] = "kong/plugins/basicauth/access.lua",
    ["kong.plugins.basicauth.schema"] = "kong/plugins/basicauth/schema.lua",
    ["kong.plugins.basicauth.api"] = "kong/plugins/basicauth/api.lua",

    ["kong.plugins.keyauth.handler"] = "kong/plugins/keyauth/handler.lua",
    ["kong.plugins.keyauth.access"] = "kong/plugins/keyauth/access.lua",
    ["kong.plugins.keyauth.schema"] = "kong/plugins/keyauth/schema.lua",
    ["kong.plugins.keyauth.api"] = "kong/plugins/keyauth/api.lua",

    ["kong.plugins.tcplog.handler"] = "kong/plugins/tcplog/handler.lua",
    ["kong.plugins.tcplog.log"] = "kong/plugins/tcplog/log.lua",
    ["kong.plugins.tcplog.schema"] = "kong/plugins/tcplog/schema.lua",

    ["kong.plugins.udplog.handler"] = "kong/plugins/udplog/handler.lua",
    ["kong.plugins.udplog.log"] = "kong/plugins/udplog/log.lua",
    ["kong.plugins.udplog.schema"] = "kong/plugins/udplog/schema.lua",

    ["kong.plugins.filelog.handler"] = "kong/plugins/filelog/handler.lua",
    ["kong.plugins.filelog.log"] = "kong/plugins/filelog/log.lua",
    ["kong.plugins.filelog.schema"] = "kong/plugins/filelog/schema.lua",

    ["kong.plugins.ratelimiting.handler"] = "kong/plugins/ratelimiting/handler.lua",
    ["kong.plugins.ratelimiting.access"] = "kong/plugins/ratelimiting/access.lua",
    ["kong.plugins.ratelimiting.schema"] = "kong/plugins/ratelimiting/schema.lua",

    ["kong.plugins.request_transformer.handler"] = "kong/plugins/request_transformer/handler.lua",
    ["kong.plugins.request_transformer.access"] = "kong/plugins/request_transformer/access.lua",
    ["kong.plugins.request_transformer.schema"] = "kong/plugins/request_transformer/schema.lua",

    ["kong.plugins.cors.handler"] = "kong/plugins/cors/handler.lua",
    ["kong.plugins.cors.access"] = "kong/plugins/cors/access.lua",
    ["kong.plugins.cors.schema"] = "kong/plugins/cors/schema.lua",

    ["kong.plugins.ssl.handler"] = "kong/plugins/ssl/handler.lua",
    ["kong.plugins.ssl.certificate"] = "kong/plugins/ssl/certificate.lua",
    ["kong.plugins.ssl.ssl_util"] = "kong/plugins/ssl/ssl_util.lua",
    ["kong.plugins.ssl.schema"] = "kong/plugins/ssl/schema.lua",

    ["kong.api.app"] = "kong/api/app.lua",
    ["kong.api.routes.apis"] = "kong/api/routes/apis.lua",
    ["kong.api.routes.consumers"] = "kong/api/routes/consumers.lua",
    ["kong.api.routes.plugins_configurations"] = "kong/api/routes/plugins_configurations.lua",
    ["kong.api.routes.base_controller"] = "kong/api/routes/base_controller.lua"
  },
  install = {
    conf = { "kong.yml" },
    bin = { "bin/kong" }
  },
  copy_directories = { "database/migrations/", "ssl" }
}
