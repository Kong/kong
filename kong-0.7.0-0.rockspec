package = "kong"
version = "0.7.0-0"
supported_platforms = {"linux", "macosx"}
source = {
  url = "git://github.com/Mashape/kong",
  tag = "0.7.0"
}
description = {
  summary = "Kong is a scalable and customizable API Management Layer built on top of Nginx.",
  homepage = "http://getkong.org",
  license = "MIT"
}
dependencies = {
  "luasec ~> 0.5-2",

  "lua_uuid ~> 0.2.0-2",
  "lua_system_constants ~> 0.1.1-0",
  "luatz ~> 0.3-1",
  "yaml ~> 1.1.2-1",
  "lapis ~> 1.3.1-1",
  "stringy ~> 0.4-1",
  "lua-cassandra ~> 0.5.0",
  "multipart ~> 0.2-1",
  "lua-path ~> 0.2.3-1",
  "lua-cjson ~> 2.1.0-1",
  "ansicolors ~> 1.0.2-3",
  "lbase64 ~> 20120820-1",
  "lua-resty-iputils ~> 0.2.0-1",
  "mediator_lua ~> 1.1.2-0",

  "luasocket ~> 2.0.2-6",
  "lrexlib-pcre ~> 2.7.2-1",
  "lua-llthreads2 ~> 0.1.3-1",
  "luacrypto >= 0.3.2-1",
  "luasyslog >= 1.0.0-2",
  "lua_ldap >= 1.0.2-0"
}
build = {
  type = "builtin",
  modules = {
    ["kong"] = "kong/kong.lua",

    ["classic"] = "kong/vendor/classic.lua",
    ["lapp"] = "kong/vendor/lapp.lua",
    ["resty_http"] = "kong/vendor/resty_http.lua",

    ["kong.constants"] = "kong/constants.lua",
    ["kong.singletons"] = "kong/singletons.lua",

    ["kong.cli.utils.logger"] = "kong/cli/utils/logger.lua",
    ["kong.cli.utils.luarocks"] = "kong/cli/utils/luarocks.lua",
    ["kong.cli.utils.ssl"] = "kong/cli/utils/ssl.lua",
    ["kong.cli.utils.input"] = "kong/cli/utils/input.lua",
    ["kong.cli.utils.services"] = "kong/cli/utils/services.lua",
    ["kong.cli.cmds.config"] = "kong/cli/cmds/config.lua",
    ["kong.cli.cmds.quit"] = "kong/cli/cmds/quit.lua",
    ["kong.cli.cmds.stop"] = "kong/cli/cmds/stop.lua",
    ["kong.cli.cmds.start"] = "kong/cli/cmds/start.lua",
    ["kong.cli.cmds.reload"] = "kong/cli/cmds/reload.lua",
    ["kong.cli.cmds.restart"] = "kong/cli/cmds/restart.lua",
    ["kong.cli.cmds.version"] = "kong/cli/cmds/version.lua",
    ["kong.cli.cmds.status"] = "kong/cli/cmds/status.lua",
    ["kong.cli.cmds.migrations"] = "kong/cli/cmds/migrations.lua",
    ["kong.cli.cmds.cluster"] = "kong/cli/cmds/cluster.lua",
    ["kong.cli.services.base_service"] = "kong/cli/services/base_service.lua",
    ["kong.cli.services.dnsmasq"] = "kong/cli/services/dnsmasq.lua",
    ["kong.cli.services.serf"] = "kong/cli/services/serf.lua",
    ["kong.cli.services.nginx"] = "kong/cli/services/nginx.lua",

    ["kong.tools.io"] = "kong/tools/io.lua",
    ["kong.tools.utils"] = "kong/tools/utils.lua",
    ["kong.tools.faker"] = "kong/tools/faker.lua",
    ["kong.tools.syslog"] = "kong/tools/syslog.lua",
    ["kong.tools.ngx_stub"] = "kong/tools/ngx_stub.lua",
    ["kong.tools.printable"] = "kong/tools/printable.lua",
    ["kong.tools.cluster"] = "kong/tools/cluster.lua",
    ["kong.tools.responses"] = "kong/tools/responses.lua",
    ["kong.tools.timestamp"] = "kong/tools/timestamp.lua",
    ["kong.tools.migrations"] = "kong/tools/migrations.lua",
    ["kong.tools.http_client"] = "kong/tools/http_client.lua",
    ["kong.tools.database_cache"] = "kong/tools/database_cache.lua",
    ["kong.tools.config_defaults"] = "kong/tools/config_defaults.lua",
    ["kong.tools.config_loader"] = "kong/tools/config_loader.lua",
    ["kong.tools.dao_loader"] = "kong/tools/dao_loader.lua",

    ["kong.core.handler"] = "kong/core/handler.lua",
    ["kong.core.certificate"] = "kong/core/certificate.lua",
    ["kong.core.resolver"] = "kong/core/resolver.lua",
    ["kong.core.plugins_iterator"] = "kong/core/plugins_iterator.lua",
    ["kong.core.hooks"] = "kong/core/hooks.lua",
    ["kong.core.reports"] = "kong/core/reports.lua",
    ["kong.core.cluster"] = "kong/core/cluster.lua",
    ["kong.core.events"] = "kong/core/events.lua",
    ["kong.core.error_handlers"] = "kong/core/error_handlers.lua",

    ["kong.dao.cassandra.schema.migrations"] = "kong/dao/cassandra/schema/migrations.lua",
    ["kong.dao.error"] = "kong/dao/error.lua",
    ["kong.dao.schemas_validation"] = "kong/dao/schemas_validation.lua",
    ["kong.dao.schemas.apis"] = "kong/dao/schemas/apis.lua",
    ["kong.dao.schemas.nodes"] = "kong/dao/schemas/nodes.lua",
    ["kong.dao.schemas.consumers"] = "kong/dao/schemas/consumers.lua",
    ["kong.dao.schemas.plugins"] = "kong/dao/schemas/plugins.lua",
    ["kong.dao.cassandra.factory"] = "kong/dao/cassandra/factory.lua",
    ["kong.dao.cassandra.query_builder"] = "kong/dao/cassandra/query_builder.lua",
    ["kong.dao.cassandra.base_dao"] = "kong/dao/cassandra/base_dao.lua",
    ["kong.dao.cassandra.migrations"] = "kong/dao/cassandra/migrations.lua",
    ["kong.dao.cassandra.apis"] = "kong/dao/cassandra/apis.lua",
    ["kong.dao.cassandra.nodes"] = "kong/dao/cassandra/nodes.lua",
    ["kong.dao.cassandra.consumers"] = "kong/dao/cassandra/consumers.lua",
    ["kong.dao.cassandra.plugins"] = "kong/dao/cassandra/plugins.lua",

    ["kong.api.app"] = "kong/api/app.lua",
    ["kong.api.crud_helpers"] = "kong/api/crud_helpers.lua",
    ["kong.api.route_helpers"] = "kong/api/route_helpers.lua",
    ["kong.api.routes.kong"] = "kong/api/routes/kong.lua",
    ["kong.api.routes.apis"] = "kong/api/routes/apis.lua",
    ["kong.api.routes.consumers"] = "kong/api/routes/consumers.lua",
    ["kong.api.routes.plugins"] = "kong/api/routes/plugins.lua",
    ["kong.api.routes.plugins"] = "kong/api/routes/plugins.lua",

    ["kong.plugins.base_plugin"] = "kong/plugins/base_plugin.lua",

    ["kong.plugins.basic-auth.schema.migrations"] = "kong/plugins/basic-auth/schema/migrations.lua",
    ["kong.plugins.basic-auth.crypto"] = "kong/plugins/basic-auth/crypto.lua",
    ["kong.plugins.basic-auth.handler"] = "kong/plugins/basic-auth/handler.lua",
    ["kong.plugins.basic-auth.access"] = "kong/plugins/basic-auth/access.lua",
    ["kong.plugins.basic-auth.schema"] = "kong/plugins/basic-auth/schema.lua",
    ["kong.plugins.basic-auth.hooks"] = "kong/plugins/basic-auth/hooks.lua",
    ["kong.plugins.basic-auth.api"] = "kong/plugins/basic-auth/api.lua",
    ["kong.plugins.basic-auth.daos"] = "kong/plugins/basic-auth/daos.lua",

    ["kong.plugins.key-auth.schema.migrations"] = "kong/plugins/key-auth/schema/migrations.lua",
    ["kong.plugins.key-auth.handler"] = "kong/plugins/key-auth/handler.lua",
    ["kong.plugins.key-auth.hooks"] = "kong/plugins/key-auth/hooks.lua",
    ["kong.plugins.key-auth.schema"] = "kong/plugins/key-auth/schema.lua",
    ["kong.plugins.key-auth.api"] = "kong/plugins/key-auth/api.lua",
    ["kong.plugins.key-auth.daos"] = "kong/plugins/key-auth/daos.lua",

    ["kong.plugins.oauth2.schema.migrations"] = "kong/plugins/oauth2/schema/migrations.lua",
    ["kong.plugins.oauth2.handler"] = "kong/plugins/oauth2/handler.lua",
    ["kong.plugins.oauth2.access"] = "kong/plugins/oauth2/access.lua",
    ["kong.plugins.oauth2.hooks"] = "kong/plugins/oauth2/hooks.lua",
    ["kong.plugins.oauth2.schema"] = "kong/plugins/oauth2/schema.lua",
    ["kong.plugins.oauth2.daos"] = "kong/plugins/oauth2/daos.lua",
    ["kong.plugins.oauth2.api"] = "kong/plugins/oauth2/api.lua",

    ["kong.plugins.log-serializers.basic"] = "kong/plugins/log-serializers/basic.lua",
    ["kong.plugins.log-serializers.alf"] = "kong/plugins/log-serializers/alf.lua",
    ["kong.plugins.log-serializers.runscope"] = "kong/plugins/log-serializers/runscope.lua",

    ["kong.plugins.tcp-log.handler"] = "kong/plugins/tcp-log/handler.lua",
    ["kong.plugins.tcp-log.schema"] = "kong/plugins/tcp-log/schema.lua",

    ["kong.plugins.udp-log.handler"] = "kong/plugins/udp-log/handler.lua",
    ["kong.plugins.udp-log.schema"] = "kong/plugins/udp-log/schema.lua",

    ["kong.plugins.http-log.handler"] = "kong/plugins/http-log/handler.lua",
    ["kong.plugins.http-log.schema"] = "kong/plugins/http-log/schema.lua",

    ["kong.plugins.file-log.handler"] = "kong/plugins/file-log/handler.lua",
    ["kong.plugins.file-log.schema"] = "kong/plugins/file-log/schema.lua",

    ["kong.plugins.runscope.handler"] = "kong/plugins/runscope/handler.lua",
    ["kong.plugins.runscope.schema"] = "kong/plugins/runscope/schema.lua",
    ["kong.plugins.runscope.buffer"] = "kong/plugins/runscope/log.lua",

    ["kong.plugins.mashape-analytics.schema.migrations"] = "kong/plugins/mashape-analytics/schema/migrations.lua",
    ["kong.plugins.mashape-analytics.handler"] = "kong/plugins/mashape-analytics/handler.lua",
    ["kong.plugins.mashape-analytics.schema"] = "kong/plugins/mashape-analytics/schema.lua",
    ["kong.plugins.mashape-analytics.buffer"] = "kong/plugins/mashape-analytics/buffer.lua",

    ["kong.plugins.rate-limiting.schema.migrations"] = "kong/plugins/rate-limiting/schema/migrations.lua",
    ["kong.plugins.rate-limiting.handler"] = "kong/plugins/rate-limiting/handler.lua",
    ["kong.plugins.rate-limiting.schema"] = "kong/plugins/rate-limiting/schema.lua",
    ["kong.plugins.rate-limiting.daos"] = "kong/plugins/rate-limiting/daos.lua",

    ["kong.plugins.response-ratelimiting.schema.migrations"] = "kong/plugins/response-ratelimiting/schema/migrations.lua",
    ["kong.plugins.response-ratelimiting.handler"] = "kong/plugins/response-ratelimiting/handler.lua",
    ["kong.plugins.response-ratelimiting.access"] = "kong/plugins/response-ratelimiting/access.lua",
    ["kong.plugins.response-ratelimiting.header_filter"] = "kong/plugins/response-ratelimiting/header_filter.lua",
    ["kong.plugins.response-ratelimiting.log"] = "kong/plugins/response-ratelimiting/log.lua",
    ["kong.plugins.response-ratelimiting.schema"] = "kong/plugins/response-ratelimiting/schema.lua",
    ["kong.plugins.response-ratelimiting.daos"] = "kong/plugins/response-ratelimiting/daos.lua",

    ["kong.plugins.request-size-limiting.handler"] = "kong/plugins/request-size-limiting/handler.lua",
    ["kong.plugins.request-size-limiting.schema"] = "kong/plugins/request-size-limiting/schema.lua",

    ["kong.plugins.request-transformer.handler"] = "kong/plugins/request-transformer/handler.lua",
    ["kong.plugins.request-transformer.access"] = "kong/plugins/request-transformer/access.lua",
    ["kong.plugins.request-transformer.schema"] = "kong/plugins/request-transformer/schema.lua",

    ["kong.plugins.response-transformer.handler"] = "kong/plugins/response-transformer/handler.lua",
    ["kong.plugins.response-transformer.body_transformer"] = "kong/plugins/response-transformer/body_transformer.lua",
    ["kong.plugins.response-transformer.header_transformer"] = "kong/plugins/response-transformer/header_transformer.lua",
    ["kong.plugins.response-transformer.schema"] = "kong/plugins/response-transformer/schema.lua",

    ["kong.plugins.cors.handler"] = "kong/plugins/cors/handler.lua",
    ["kong.plugins.cors.schema"] = "kong/plugins/cors/schema.lua",

    ["kong.plugins.ssl.handler"] = "kong/plugins/ssl/handler.lua",
    ["kong.plugins.ssl.hooks"] = "kong/plugins/ssl/hooks.lua",
    ["kong.plugins.ssl.schema"] = "kong/plugins/ssl/schema.lua",

    ["kong.plugins.ip-restriction.handler"] = "kong/plugins/ip-restriction/handler.lua",
    ["kong.plugins.ip-restriction.schema"] = "kong/plugins/ip-restriction/schema.lua",

    ["kong.plugins.acl.schema.migrations"] = "kong/plugins/acl/schema/migrations.lua",
    ["kong.plugins.acl.handler"] = "kong/plugins/acl/handler.lua",
    ["kong.plugins.acl.schema"] = "kong/plugins/acl/schema.lua",
    ["kong.plugins.acl.hooks"] = "kong/plugins/acl/hooks.lua",
    ["kong.plugins.acl.api"] = "kong/plugins/acl/api.lua",
    ["kong.plugins.acl.daos"] = "kong/plugins/acl/daos.lua",

    ["kong.api.app"] = "kong/api/app.lua",
    ["kong.api.crud_helpers"] = "kong/api/crud_helpers.lua",
    ["kong.api.route_helpers"] = "kong/api/route_helpers.lua",
    ["kong.api.routes.kong"] = "kong/api/routes/kong.lua",
    ["kong.api.routes.apis"] = "kong/api/routes/apis.lua",
    ["kong.api.routes.consumers"] = "kong/api/routes/consumers.lua",
    ["kong.api.routes.plugins"] = "kong/api/routes/plugins.lua",
    ["kong.api.routes.cache"] = "kong/api/routes/cache.lua",
    ["kong.api.routes.cluster"] = "kong/api/routes/cluster.lua",

    ["kong.plugins.jwt.schema.migrations"] = "kong/plugins/jwt/schema/migrations.lua",
    ["kong.plugins.jwt.handler"] = "kong/plugins/jwt/handler.lua",
    ["kong.plugins.jwt.schema"] = "kong/plugins/jwt/schema.lua",
    ["kong.plugins.jwt.hooks"] = "kong/plugins/jwt/hooks.lua",
    ["kong.plugins.jwt.api"] = "kong/plugins/jwt/api.lua",
    ["kong.plugins.jwt.daos"] = "kong/plugins/jwt/daos.lua",
    ["kong.plugins.jwt.jwt_parser"] = "kong/plugins/jwt/jwt_parser.lua",

    ["kong.plugins.hmac-auth.schema.migrations"] = "kong/plugins/hmac-auth/schema/migrations.lua",
    ["kong.plugins.hmac-auth.handler"] = "kong/plugins/hmac-auth/handler.lua",
    ["kong.plugins.hmac-auth.access"] = "kong/plugins/hmac-auth/access.lua",
    ["kong.plugins.hmac-auth.schema"] = "kong/plugins/hmac-auth/schema.lua",
    ["kong.plugins.hmac-auth.hooks"] = "kong/plugins/hmac-auth/hooks.lua",
    ["kong.plugins.hmac-auth.api"] = "kong/plugins/hmac-auth/api.lua",
    ["kong.plugins.hmac-auth.daos"] = "kong/plugins/hmac-auth/daos.lua",

    ["kong.plugins.syslog.handler"] = "kong/plugins/syslog/handler.lua",
    ["kong.plugins.syslog.schema"] = "kong/plugins/syslog/schema.lua",

    ["kong.plugins.loggly.handler"] = "kong/plugins/loggly/handler.lua",
    ["kong.plugins.loggly.schema"] = "kong/plugins/loggly/schema.lua",

    ["kong.plugins.datadog.handler"] = "kong/plugins/datadog/handler.lua",
    ["kong.plugins.datadog.schema"] = "kong/plugins/datadog/schema.lua",
    ["kong.plugins.datadog.statsd_logger"] = "kong/plugins/datadog/statsd_logger.lua",
    
    ["kong.plugins.ldap-auth.handler"] = "kong/plugins/ldap-auth/handler.lua",
    ["kong.plugins.ldap-auth.access"] = "kong/plugins/ldap-auth/access.lua",
    ["kong.plugins.ldap-auth.schema"] = "kong/plugins/ldap-auth/schema.lua",
    ["kong.plugins.ldap-auth.ldap_authentication"] = "kong/plugins/ldap-auth/ldap_authentication.lua"

  },
  install = {
    conf = { "kong.yml" },
    bin = { "bin/kong" }
  }
}
