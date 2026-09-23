local typedefs = require "kong.db.schema.typedefs"

-- If you add more configuration parameters, be sure to check if it needs to be added to cache key
-- Fields currently used for cache_key: ldap_host, ldap_port, base_dn, attribute, cache_ttl

return {
  name = "ldap-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { ldap_host = typedefs.host({ required = true }), },
          { ldap_port = typedefs.port({ required = true, default = 389 }), },
          { ldaps = { description = "Set to `true` to connect using the LDAPS protocol (LDAP over TLS).  When `ldaps` is configured, you must use port 636. If the `ldap` setting is enabled, ensure the `start_tls` setting is disabled.", type = "boolean", required = true, default = false } },
          { start_tls = { description = "Set it to `true` to issue StartTLS (Transport Layer Security) extended operation over `ldap` connection. If the `start_tls` setting is enabled, ensure the `ldaps` setting is disabled.", type = "boolean", required = true, default = false }, },
          { verify_ldap_host = { description = "Set to `true` to authenticate LDAP server. The server certificate will be verified according to the CA certificates specified by the `lua_ssl_trusted_certificate` directive.", type = "boolean", required = true, default = false }, },
          { base_dn = { description = "Base DN as the starting point for the search; e.g., dc=example,dc=com", type = "string", required = true }, },
          { attribute = { description = "Attribute to be used to search the user; e.g. cn", type = "string", required = true }, },
          { cache_ttl = { description = "Cache expiry time in seconds.", type = "number", required = true, default = 60 }, },
          { hide_credentials = { description = "An optional boolean value telling the plugin to hide the credential to the upstream server. It will be removed by Kong before proxying the request.", type = "boolean", required = true, default = false }, },
          { timeout = { description = "An optional timeout in milliseconds when waiting for connection with LDAP server.", type = "number", default = 10000 }, },
          { keepalive = { description = "An optional value in milliseconds that defines how long an idle connection to LDAP server will live before being closed.", type = "number", default = 60000 }, },
          { anonymous = { description = "An optional string (consumer UUID or username) value to use as an “anonymous” consumer if authentication fails. If empty (default null), the request fails with an authentication failure `4xx`.", type = "string" }, },
          { header_type = { description = "An optional string to use as part of the Authorization header",  type = "string", default = "ldap" }, },
          { realm = { description = "When authentication fails the plugin sends `WWW-Authenticate` header with `realm` attribute value.", type = "string", required = false }, },
        },
        entity_checks = {
          { conditional = {
            if_field   = "ldaps",     if_match   = { eq = true },
            then_field = "start_tls", then_match = { eq = false },
            then_err   = "'ldaps' and 'start_tls' cannot be enabled simultaneously"
          } },
        }
    }, },
  },
}
