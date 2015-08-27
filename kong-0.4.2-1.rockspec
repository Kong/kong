package = "kong"
version = "0.4.2-1"
supported_platforms = {"linux", "macosx"}
source = {
  url = "git://github.com/Mashape/kong",
  tag = "0.4.2"
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
  "lua-cassandra ~> 0.3.6-0",
  "multipart ~> 0.1-3",
  "lua-path ~> 0.2.3-1",
  "lua-cjson ~> 2.1.0-1",
  "ansicolors ~> 1.0.2-3",
  "lbase64 ~> 20120820-1",
  "lua-resty-iputils ~> 0.2.0-1",

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
    ["ngx.ssl"] = "kong/vendor/ssl.lua",
    ["resty_http"] = "kong/vendor/resty_http.lua",

    ["kong.constants"] = "kong/constants.lua",

    ["kong.cli.utils"] = "kong/cli/utils/utils.lua",
    ["kong.cli.utils.dnsmasq"] = "kong/cli/utils/dnsmasq.lua",
    ["kong.cli.utils.ssl"] = "kong/cli/utils/ssl.lua",
    ["kong.cli.utils.signal"] = "kong/cli/utils/signal.lua",
    ["kong.cli.utils.input"] = "kong/cli/utils/input.lua",
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

    ["kong.reports.handler"] = "kong/reports/handler.lua",
    ["kong.reports.init_worker"] = "kong/reports/init_worker.lua",
    ["kong.reports.log"] = "kong/reports/log.lua",

    ["kong.dao.cassandra.schema.migrations"] = "kong/dao/cassandra/schema/migrations.lua",
    ["kong.dao.error"] = "kong/dao/error.lua",
    ["kong.dao.schemas_validation"] = "kong/dao/schemas_validation.lua",
    ["kong.dao.schemas.apis"] = "kong/dao/schemas/apis.lua",
    ["kong.dao.schemas.consumers"] = "kong/dao/schemas/consumers.lua",
    ["kong.dao.schemas.plugins_configurations"] = "kong/dao/schemas/plugins_configurations.lua",
    ["kong.dao.cassandra.factory"] = "kong/dao/cassandra/factory.lua",
    ["kong.dao.cassandra.query_builder"] = "kong/dao/cassandra/query_builder.lua",
    ["kong.dao.cassandra.base_dao"] = "kong/dao/cassandra/base_dao.lua",
    ["kong.dao.cassandra.migrations"] = "kong/dao/cassandra/migrations.lua",
    ["kong.dao.cassandra.apis"] = "kong/dao/cassandra/apis.lua",
    ["kong.dao.cassandra.consumers"] = "kong/dao/cassandra/consumers.lua",
    ["kong.dao.cassandra.plugins_configurations"] = "kong/dao/cassandra/plugins_configurations.lua",

    ["kong.plugins.base_plugin"] = "kong/plugins/base_plugin.lua",

    ["kong.plugins.basic-auth.migrations.cassandra"] = "kong/plugins/basic-auth/migrations/cassandra.lua",
    ["kong.plugins.basic-auth.handler"] = "kong/plugins/basic-auth/handler.lua",
    ["kong.plugins.basic-auth.access"] = "kong/plugins/basic-auth/access.lua",
    ["kong.plugins.basic-auth.schema"] = "kong/plugins/basic-auth/schema.lua",
    ["kong.plugins.basic-auth.api"] = "kong/plugins/basic-auth/api.lua",
    ["kong.plugins.basic-auth.daos"] = "kong/plugins/basic-auth/daos.lua",

    ["kong.plugins.key-auth.migrations.cassandra"] = "kong/plugins/key-auth/migrations/cassandra.lua",
    ["kong.plugins.key-auth.handler"] = "kong/plugins/key-auth/handler.lua",
    ["kong.plugins.key-auth.access"] = "kong/plugins/key-auth/access.lua",
    ["kong.plugins.key-auth.schema"] = "kong/plugins/key-auth/schema.lua",
    ["kong.plugins.key-auth.api"] = "kong/plugins/key-auth/api.lua",
    ["kong.plugins.key-auth.daos"] = "kong/plugins/key-auth/daos.lua",

    ["kong.plugins.oauth2.migrations.cassandra"] = "kong/plugins/oauth2/migrations/cassandra.lua",
    ["kong.plugins.oauth2.handler"] = "kong/plugins/oauth2/handler.lua",
    ["kong.plugins.oauth2.access"] = "kong/plugins/oauth2/access.lua",
    ["kong.plugins.oauth2.schema"] = "kong/plugins/oauth2/schema.lua",
    ["kong.plugins.oauth2.daos"] = "kong/plugins/oauth2/daos.lua",
    ["kong.plugins.oauth2.api"] = "kong/plugins/oauth2/api.lua",

    ["kong.plugins.log-serializers.basic"] = "kong/plugins/log-serializers/basic.lua",
    ["kong.plugins.log-serializers.alf"] = "kong/plugins/log-serializers/alf.lua",

    ["kong.plugins.tcp-log.handler"] = "kong/plugins/tcp-log/handler.lua",
    ["kong.plugins.tcp-log.log"] = "kong/plugins/tcp-log/log.lua",
    ["kong.plugins.tcp-log.schema"] = "kong/plugins/tcp-log/schema.lua",

    ["kong.plugins.udp-log.handler"] = "kong/plugins/udp-log/handler.lua",
    ["kong.plugins.udp-log.log"] = "kong/plugins/udp-log/log.lua",
    ["kong.plugins.udp-log.schema"] = "kong/plugins/udp-log/schema.lua",

    ["kong.plugins.http-log.handler"] = "kong/plugins/http-log/handler.lua",
    ["kong.plugins.http-log.log"] = "kong/plugins/http-log/log.lua",
    ["kong.plugins.http-log.schema"] = "kong/plugins/http-log/schema.lua",

    ["kong.plugins.file-log.handler"] = "kong/plugins/file-log/handler.lua",
    ["kong.plugins.file-log.schema"] = "kong/plugins/file-log/schema.lua",
    ["kong.plugins.file-log.log"] = "kong/plugins/file-log/log.lua",
    ["kong.plugins.file-log.fd_util"] = "kong/plugins/file-log/fd_util.lua",

    ["kong.plugins.mashape-analytics.handler"] = "kong/plugins/mashape-analytics/handler.lua",
    ["kong.plugins.mashape-analytics.schema"] = "kong/plugins/mashape-analytics/schema.lua",
    ["kong.plugins.mashape-analytics.buffer"] = "kong/plugins/mashape-analytics/buffer.lua",

    ["kong.plugins.rate-limiting.migrations.cassandra"] = "kong/plugins/rate-limiting/migrations/cassandra.lua",
    ["kong.plugins.rate-limiting.handler"] = "kong/plugins/rate-limiting/handler.lua",
    ["kong.plugins.rate-limiting.access"] = "kong/plugins/rate-limiting/access.lua",
    ["kong.plugins.rate-limiting.schema"] = "kong/plugins/rate-limiting/schema.lua",
    ["kong.plugins.rate-limiting.daos"] = "kong/plugins/rate-limiting/daos.lua",

    ["kong.plugins.response-ratelimiting.migrations.cassandra"] = "kong/plugins/response-ratelimiting/migrations/cassandra.lua",
    ["kong.plugins.response-ratelimiting.handler"] = "kong/plugins/response-ratelimiting/handler.lua",
    ["kong.plugins.response-ratelimiting.access"] = "kong/plugins/response-ratelimiting/access.lua",
    ["kong.plugins.response-ratelimiting.header_filter"] = "kong/plugins/response-ratelimiting/header_filter.lua",
    ["kong.plugins.response-ratelimiting.log"] = "kong/plugins/response-ratelimiting/log.lua",
    ["kong.plugins.response-ratelimiting.schema"] = "kong/plugins/response-ratelimiting/schema.lua",
    ["kong.plugins.response-ratelimiting.daos"] = "kong/plugins/response-ratelimiting/daos.lua",

    ["kong.plugins.request-size-limiting.handler"] = "kong/plugins/request-size-limiting/handler.lua",
    ["kong.plugins.request-size-limiting.access"] = "kong/plugins/request-size-limiting/access.lua",
    ["kong.plugins.request-size-limiting.schema"] = "kong/plugins/request-size-limiting/schema.lua",

    ["kong.plugins.request-transformer.handler"] = "kong/plugins/request-transformer/handler.lua",
    ["kong.plugins.request-transformer.access"] = "kong/plugins/request-transformer/access.lua",
    ["kong.plugins.request-transformer.schema"] = "kong/plugins/request-transformer/schema.lua",

    ["kong.plugins.response-transformer.handler"] = "kong/plugins/response-transformer/handler.lua",
    ["kong.plugins.response-transformer.body_filter"] = "kong/plugins/response-transformer/body_filter.lua",
    ["kong.plugins.response-transformer.header_filter"] = "kong/plugins/response-transformer/header_filter.lua",
    ["kong.plugins.response-transformer.schema"] = "kong/plugins/response-transformer/schema.lua",

    ["kong.plugins.cors.handler"] = "kong/plugins/cors/handler.lua",
    ["kong.plugins.cors.access"] = "kong/plugins/cors/access.lua",
    ["kong.plugins.cors.schema"] = "kong/plugins/cors/schema.lua",

    ["kong.plugins.ssl.handler"] = "kong/plugins/ssl/handler.lua",
    ["kong.plugins.ssl.certificate"] = "kong/plugins/ssl/certificate.lua",
    ["kong.plugins.ssl.access"] = "kong/plugins/ssl/access.lua",
    ["kong.plugins.ssl.ssl_util"] = "kong/plugins/ssl/ssl_util.lua",
    ["kong.plugins.ssl.schema"] = "kong/plugins/ssl/schema.lua",

    ["kong.plugins.ip-restriction.handler"] = "kong/plugins/ip-restriction/handler.lua",
    ["kong.plugins.ip-restriction.init_worker"] = "kong/plugins/ip-restriction/init_worker.lua",
    ["kong.plugins.ip-restriction.access"] = "kong/plugins/ip-restriction/access.lua",
    ["kong.plugins.ip-restriction.schema"] = "kong/plugins/ip-restriction/schema.lua",

    ["kong.api.app"] = "kong/api/app.lua",
    ["kong.api.crud_helpers"] = "kong/api/crud_helpers.lua",
    ["kong.api.route_helpers"] = "kong/api/route_helpers.lua",
    ["kong.api.routes.kong"] = "kong/api/routes/kong.lua",
    ["kong.api.routes.apis"] = "kong/api/routes/apis.lua",
    ["kong.api.routes.consumers"] = "kong/api/routes/consumers.lua",
    ["kong.api.routes.plugins"] = "kong/api/routes/plugins.lua",
    ["kong.api.routes.plugins_configurations"] = "kong/api/routes/plugins_configurations.lua",
  },
  install = {
    conf = { "kong.yml" },
    bin = { "bin/kong" }
  }
}
