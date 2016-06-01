package = "kong"
version = "0.8.3-0"
supported_platforms = {"linux", "macosx"}
source = {
  url = "git://github.com/Mashape/kong",
  tag = "0.8.3"
}
description = {
  summary = "Kong is a scalable and customizable API Management Layer built on top of Nginx.",
  homepage = "http://getkong.org",
  license = "MIT"
}
dependencies = {
  "luasec ~> 0.5-2",

  "penlight ~> 1.3.2",
  "lua-resty-http ~> 0.07-0",
  "lua_uuid ~> 0.2.0-2",
  "lua_system_constants ~> 0.1.1-0",
  "luatz ~> 0.3-1",
  "yaml ~> 1.1.2-1",
  "lapis ~> 1.3.1-1",
  "stringy ~> 0.4-1",
  "lua-cassandra ~> 0.5.2",
  "pgmoon ~> 1.4.0",
  "multipart ~> 0.3-2",
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
  "lua_pack ~> 1.0.4-0"
}
build = {
  type = "builtin",
  modules = {
    ["kong"] = "kong/kong.lua",

    ["classic"] = "kong/vendor/classic.lua",
    ["lapp"] = "kong/vendor/lapp.lua",

    ["kong.meta"] = "kong/meta.lua",
    ["kong.constants"] = "kong/constants.lua",
    ["kong.singletons"] = "kong/singletons.lua",

    ["kong.cli.utils.logger"] = "kong/cli/utils/logger.lua",
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

    ["kong.api.app"] = "kong/api/app.lua",
    ["kong.api.api_helpers"] = "kong/api/api_helpers.lua",
    ["kong.api.crud_helpers"] = "kong/api/crud_helpers.lua",
    ["kong.api.routes.kong"] = "kong/api/routes/kong.lua",
    ["kong.api.routes.apis"] = "kong/api/routes/apis.lua",
    ["kong.api.routes.consumers"] = "kong/api/routes/consumers.lua",
    ["kong.api.routes.plugins"] = "kong/api/routes/plugins.lua",
    ["kong.api.routes.cache"] = "kong/api/routes/cache.lua",
    ["kong.api.routes.cluster"] = "kong/api/routes/cluster.lua",

    ["kong.tools.io"] = "kong/tools/io.lua",
    ["kong.tools.utils"] = "kong/tools/utils.lua",
    ["kong.tools.faker"] = "kong/tools/faker.lua",
    ["kong.tools.syslog"] = "kong/tools/syslog.lua",
    ["kong.tools.ngx_stub"] = "kong/tools/ngx_stub.lua",
    ["kong.tools.printable"] = "kong/tools/printable.lua",
    ["kong.tools.cluster"] = "kong/tools/cluster.lua",
    ["kong.tools.responses"] = "kong/tools/responses.lua",
    ["kong.tools.timestamp"] = "kong/tools/timestamp.lua",
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

    ["kong.dao.errors"] = "kong/dao/errors.lua",
    ["kong.dao.schemas_validation"] = "kong/dao/schemas_validation.lua",
    ["kong.dao.schemas.apis"] = "kong/dao/schemas/apis.lua",
    ["kong.dao.schemas.nodes"] = "kong/dao/schemas/nodes.lua",
    ["kong.dao.schemas.consumers"] = "kong/dao/schemas/consumers.lua",
    ["kong.dao.schemas.plugins"] = "kong/dao/schemas/plugins.lua",
    ["kong.dao.base_db"] = "kong/dao/base_db.lua",
    ["kong.dao.cassandra_db"] = "kong/dao/cassandra_db.lua",
    ["kong.dao.postgres_db"] = "kong/dao/postgres_db.lua",
    ["kong.dao.dao"] = "kong/dao/dao.lua",
    ["kong.dao.factory"] = "kong/dao/factory.lua",
    ["kong.dao.model_factory"] = "kong/dao/model_factory.lua",
    ["kong.dao.migrations.cassandra"] = "kong/dao/migrations/cassandra.lua",
    ["kong.dao.migrations.postgres"] = "kong/dao/migrations/postgres.lua",

    ["kong.plugins.base_plugin"] = "kong/plugins/base_plugin.lua",

    ["kong.plugins.basic-auth.migrations.cassandra"] = "kong/plugins/basic-auth/migrations/cassandra.lua",
    ["kong.plugins.basic-auth.migrations.postgres"] = "kong/plugins/basic-auth/migrations/postgres.lua",
    ["kong.plugins.basic-auth.crypto"] = "kong/plugins/basic-auth/crypto.lua",
    ["kong.plugins.basic-auth.handler"] = "kong/plugins/basic-auth/handler.lua",
    ["kong.plugins.basic-auth.access"] = "kong/plugins/basic-auth/access.lua",
    ["kong.plugins.basic-auth.schema"] = "kong/plugins/basic-auth/schema.lua",
    ["kong.plugins.basic-auth.hooks"] = "kong/plugins/basic-auth/hooks.lua",
    ["kong.plugins.basic-auth.api"] = "kong/plugins/basic-auth/api.lua",
    ["kong.plugins.basic-auth.daos"] = "kong/plugins/basic-auth/daos.lua",

    ["kong.plugins.key-auth.migrations.cassandra"] = "kong/plugins/key-auth/migrations/cassandra.lua",
    ["kong.plugins.key-auth.migrations.postgres"] = "kong/plugins/key-auth/migrations/postgres.lua",
    ["kong.plugins.key-auth.handler"] = "kong/plugins/key-auth/handler.lua",
    ["kong.plugins.key-auth.hooks"] = "kong/plugins/key-auth/hooks.lua",
    ["kong.plugins.key-auth.schema"] = "kong/plugins/key-auth/schema.lua",
    ["kong.plugins.key-auth.api"] = "kong/plugins/key-auth/api.lua",
    ["kong.plugins.key-auth.daos"] = "kong/plugins/key-auth/daos.lua",

    ["kong.plugins.oauth2.migrations.cassandra"] = "kong/plugins/oauth2/migrations/cassandra.lua",
    ["kong.plugins.oauth2.migrations.postgres"] = "kong/plugins/oauth2/migrations/postgres.lua",
    ["kong.plugins.oauth2.handler"] = "kong/plugins/oauth2/handler.lua",
    ["kong.plugins.oauth2.access"] = "kong/plugins/oauth2/access.lua",
    ["kong.plugins.oauth2.hooks"] = "kong/plugins/oauth2/hooks.lua",
    ["kong.plugins.oauth2.schema"] = "kong/plugins/oauth2/schema.lua",
    ["kong.plugins.oauth2.daos"] = "kong/plugins/oauth2/daos.lua",
    ["kong.plugins.oauth2.api"] = "kong/plugins/oauth2/api.lua",

    ["kong.plugins.log-serializers.basic"] = "kong/plugins/log-serializers/basic.lua",
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
    ["kong.plugins.runscope.log"] = "kong/plugins/runscope/log.lua",

    ["kong.plugins.galileo.migrations.cassandra"] = "kong/plugins/galileo/migrations/cassandra.lua",
    ["kong.plugins.galileo.migrations.postgres"] = "kong/plugins/galileo/migrations/postgres.lua",
    ["kong.plugins.galileo.handler"] = "kong/plugins/galileo/handler.lua",
    ["kong.plugins.galileo.schema"] = "kong/plugins/galileo/schema.lua",
    ["kong.plugins.galileo.buffer"] = "kong/plugins/galileo/buffer.lua",
    ["kong.plugins.galileo.alf"] = "kong/plugins/galileo/alf.lua",

    ["kong.plugins.rate-limiting.migrations.cassandra"] = "kong/plugins/rate-limiting/migrations/cassandra.lua",
    ["kong.plugins.rate-limiting.migrations.postgres"] = "kong/plugins/rate-limiting/migrations/postgres.lua",
    ["kong.plugins.rate-limiting.handler"] = "kong/plugins/rate-limiting/handler.lua",
    ["kong.plugins.rate-limiting.schema"] = "kong/plugins/rate-limiting/schema.lua",
    ["kong.plugins.rate-limiting.dao.cassandra"] = "kong/plugins/rate-limiting/dao/cassandra.lua",
    ["kong.plugins.rate-limiting.dao.postgres"] = "kong/plugins/rate-limiting/dao/postgres.lua",

    ["kong.plugins.response-ratelimiting.migrations.cassandra"] = "kong/plugins/response-ratelimiting/migrations/cassandra.lua",
    ["kong.plugins.response-ratelimiting.migrations.postgres"] = "kong/plugins/response-ratelimiting/migrations/postgres.lua",
    ["kong.plugins.response-ratelimiting.handler"] = "kong/plugins/response-ratelimiting/handler.lua",
    ["kong.plugins.response-ratelimiting.access"] = "kong/plugins/response-ratelimiting/access.lua",
    ["kong.plugins.response-ratelimiting.header_filter"] = "kong/plugins/response-ratelimiting/header_filter.lua",
    ["kong.plugins.response-ratelimiting.log"] = "kong/plugins/response-ratelimiting/log.lua",
    ["kong.plugins.response-ratelimiting.schema"] = "kong/plugins/response-ratelimiting/schema.lua",
    ["kong.plugins.response-ratelimiting.dao.cassandra"] = "kong/plugins/response-ratelimiting/dao/cassandra.lua",
    ["kong.plugins.response-ratelimiting.dao.postgres"] = "kong/plugins/response-ratelimiting/dao/postgres.lua",

    ["kong.plugins.request-size-limiting.handler"] = "kong/plugins/request-size-limiting/handler.lua",
    ["kong.plugins.request-size-limiting.schema"] = "kong/plugins/request-size-limiting/schema.lua",

    ["kong.plugins.request-transformer.migrations.cassandra"] = "kong/plugins/request-transformer/migrations/cassandra.lua",
    ["kong.plugins.request-transformer.handler"] = "kong/plugins/request-transformer/handler.lua",
    ["kong.plugins.request-transformer.access"] = "kong/plugins/request-transformer/access.lua",
    ["kong.plugins.request-transformer.schema"] = "kong/plugins/request-transformer/schema.lua",

    ["kong.plugins.response-transformer.migrations.cassandra"] = "kong/plugins/response-transformer/migrations/cassandra.lua",
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
    ["kong.plugins.ip-restriction.migrations.cassandra"] = "kong/plugins/ip-restriction/migrations/cassandra.lua",
    ["kong.plugins.ip-restriction.migrations.postgres"] = "kong/plugins/ip-restriction/migrations/postgres.lua",

    ["kong.plugins.acl.migrations.cassandra"] = "kong/plugins/acl/migrations/cassandra.lua",
    ["kong.plugins.acl.migrations.postgres"] = "kong/plugins/acl/migrations/postgres.lua",
    ["kong.plugins.acl.handler"] = "kong/plugins/acl/handler.lua",
    ["kong.plugins.acl.schema"] = "kong/plugins/acl/schema.lua",
    ["kong.plugins.acl.hooks"] = "kong/plugins/acl/hooks.lua",
    ["kong.plugins.acl.api"] = "kong/plugins/acl/api.lua",
    ["kong.plugins.acl.daos"] = "kong/plugins/acl/daos.lua",

    ["kong.plugins.correlation-id.handler"] = "kong/plugins/correlation-id/handler.lua",
    ["kong.plugins.correlation-id.schema"] = "kong/plugins/correlation-id/schema.lua",

    ["kong.plugins.jwt.migrations.cassandra"] = "kong/plugins/jwt/migrations/cassandra.lua",
    ["kong.plugins.jwt.migrations.postgres"] = "kong/plugins/jwt/migrations/postgres.lua",
    ["kong.plugins.jwt.handler"] = "kong/plugins/jwt/handler.lua",
    ["kong.plugins.jwt.schema"] = "kong/plugins/jwt/schema.lua",
    ["kong.plugins.jwt.hooks"] = "kong/plugins/jwt/hooks.lua",
    ["kong.plugins.jwt.api"] = "kong/plugins/jwt/api.lua",
    ["kong.plugins.jwt.daos"] = "kong/plugins/jwt/daos.lua",
    ["kong.plugins.jwt.jwt_parser"] = "kong/plugins/jwt/jwt_parser.lua",

    ["kong.plugins.hmac-auth.migrations.cassandra"] = "kong/plugins/hmac-auth/migrations/cassandra.lua",
    ["kong.plugins.hmac-auth.migrations.postgres"] = "kong/plugins/hmac-auth/migrations/postgres.lua",
    ["kong.plugins.hmac-auth.handler"] = "kong/plugins/hmac-auth/handler.lua",
    ["kong.plugins.hmac-auth.access"] = "kong/plugins/hmac-auth/access.lua",
    ["kong.plugins.hmac-auth.schema"] = "kong/plugins/hmac-auth/schema.lua",
    ["kong.plugins.hmac-auth.hooks"] = "kong/plugins/hmac-auth/hooks.lua",
    ["kong.plugins.hmac-auth.api"] = "kong/plugins/hmac-auth/api.lua",
    ["kong.plugins.hmac-auth.daos"] = "kong/plugins/hmac-auth/daos.lua",

    ["kong.plugins.ldap-auth.handler"] = "kong/plugins/ldap-auth/handler.lua",
    ["kong.plugins.ldap-auth.access"] = "kong/plugins/ldap-auth/access.lua",
    ["kong.plugins.ldap-auth.schema"] = "kong/plugins/ldap-auth/schema.lua",
    ["kong.plugins.ldap-auth.ldap"] = "kong/plugins/ldap-auth/ldap.lua",
    ["kong.plugins.ldap-auth.asn1"] = "kong/plugins/ldap-auth/asn1.lua",

    ["kong.plugins.syslog.handler"] = "kong/plugins/syslog/handler.lua",
    ["kong.plugins.syslog.schema"] = "kong/plugins/syslog/schema.lua",

    ["kong.plugins.loggly.handler"] = "kong/plugins/loggly/handler.lua",
    ["kong.plugins.loggly.schema"] = "kong/plugins/loggly/schema.lua",

    ["kong.plugins.datadog.handler"] = "kong/plugins/datadog/handler.lua",
    ["kong.plugins.datadog.schema"] = "kong/plugins/datadog/schema.lua",
    ["kong.plugins.datadog.statsd_logger"] = "kong/plugins/datadog/statsd_logger.lua",

    ["kong.plugins.statsd.handler"] = "kong/plugins/statsd/handler.lua",
    ["kong.plugins.statsd.schema"] = "kong/plugins/statsd/schema.lua",
    ["kong.plugins.statsd.statsd_logger"] = "kong/plugins/statsd/statsd_logger.lua"
  },
  install = {
    conf = { "kong.yml" },
    bin = { "bin/kong" }
  }
}
