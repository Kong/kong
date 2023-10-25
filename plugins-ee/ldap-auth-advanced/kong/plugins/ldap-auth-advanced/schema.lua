-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


local function check_ldaps_tls(entity)
  local ldaps = entity.config.ldaps
  local start_tls = entity.config.start_tls

  if ldaps and start_tls then
    return nil, "ldaps and StartTLS cannot be enabled simultaneously."
  end
  return true
end

-- If you add more configuration parameters, be sure to check if it needs to be added to cache key

return {
  name = "ldap-auth-advanced",
  fields = {
    { protocols = typedefs.protocols_http_and_ws },
    { consumer_group = typedefs.no_consumer_group },
    { consumer = typedefs.no_consumer },
    { config = {
      type = "record",
      fields = {
        { ldap_host = { description = "Host on which the LDAP server is running.", type = "string",
          required = true,
        }},
        { ldap_password = { description = "The password to the LDAP server.", type = "string",
          encrypted = true,
          referenceable = true,
        }},
        { ldap_port = { description = "TCP port where the LDAP server is listening. 389 is the default port for non-SSL LDAP and AD. 636 is the port required for SSL LDAP and AD. If `ldaps` is configured, you must use port 636.", type = "number",
          default = 389
        }},
        { bind_dn = { description = "The DN to bind to. Used to perform LDAP search of user. This `bind_dn` should have permissions to search for the user being authenticated.", type = "string",
          referenceable = true,
        }},
        { ldaps = { description = "Set it to `true` to use `ldaps`, a secure protocol (that can be configured to TLS) to connect to the LDAP server. When `ldaps` is configured, you must use port 636. If the `ldap` setting is enabled, ensure the `start_tls` setting is disabled.", type = "boolean",
          required = true,
          default = false
        }},
        { start_tls = { description = "Set it to `true` to issue StartTLS (Transport Layer Security) extended operation over `ldap` connection. If the `start_tls` setting is enabled, ensure the `ldaps` setting is disabled.", type = "boolean",
          required = true,
          default = false
        }},
        { verify_ldap_host = { description = "Set to `true` to authenticate LDAP server. The server certificate will be verified according to the CA certificates specified by the `lua_ssl_trusted_certificate` directive.", type = "boolean",
          required = true,
          default = false
        }},
        { base_dn = { description = "Base DN as the starting point for the search; e.g., 'dc=example,dc=com'.", type = "string",
          required = true
        }},                            -- used for cache key
        { attribute = { description = "Attribute to be used to search the user; e.g., \"cn\".", type = "string",
          required = true
        }},                          -- used for cache key
        { cache_ttl = { description = "Cache expiry time in seconds.", type = "number",
          required = true,
          default = 60
        }},            -- used for cache key
        { hide_credentials = { description = "An optional boolean value telling the plugin to hide the credential to the upstream server. It will be removed by Kong before proxying the request.", type = "boolean",
          default = false
        }},
        { timeout = { description = "An optional timeout in milliseconds when waiting for connection with LDAP server.", type = "number",
          default = 10000
        }},
        { keepalive = { description = "An optional value in milliseconds that defines how long an idle connection to LDAP server will live before being closed.", type = "number",
          default = 60000
        }},
        { anonymous = { description = "An optional string (consumer UUID or username) value to use as an “anonymous” consumer if authentication fails. If empty (default null), the request will fail with an authentication failure `4xx`. Note that this value must refer to the consumer `id` or `username` attribute, and **not** its `custom_id`.", type = "string",
          len_min = 0,
          default = "",
        }},
        { header_type = { description = "An optional string to use as part of the Authorization header. By default, a valid Authorization header looks like this: `Authorization: ldap base64(username:password)`. If `header_type` is set to \"basic\", then the Authorization header would be `Authorization: basic base64(username:password)`. Note that `header_type` can take any string, not just `'ldap'` and `'basic'`.",
          type = "string",
          default = "ldap"
        }},
        { consumer_optional = { description = "Whether consumer mapping is optional. If `consumer_optional=true`, the plugin will not attempt to associate a consumer with the LDAP authenticated user.", type = "boolean",
          required = false,
          default = false
        }},
        { consumer_by = { description = "Whether to authenticate consumers based on `username`, `custom_id`, or both.", type = "array",
          elements = { type = "string", one_of = { "username", "custom_id" }},
          required = false,
          default = { "username", "custom_id" },
        }},
        { group_base_dn = { description = "Sets a distinguished name (DN) for the entry where LDAP searches for groups begin. This field is case-insensitive.',dc=com'.", type = "string"
        }},
        { group_name_attribute = { description = "Sets the attribute holding the name of a group, typically called `name` (in Active Directory) or `cn` (in OpenLDAP). This field is case-insensitive.", type = "string"
        }},
        { group_member_attribute = { description = "Sets the attribute holding the members of the LDAP group. This field is case-sensitive.", type = "string",
          default = "memberOf"
        }},
        { log_search_results = { description = "Displays all the LDAP search results received from the LDAP server for debugging purposes. Not recommended to be enabled in a production environment.", type = "boolean",
          required = false,
          default = false,
        }},
        { groups_required = { description = "The groups required to be present in the LDAP search result for successful authorization. This config parameter works in both **AND** / **OR** cases. - When `[\"group1 group2\"]` are in the same array indices, both `group1` AND `group2` need to be present in the LDAP search result. - When `[\"group1\", \"group2\"]` are in different array indices, either `group1` OR `group2` need to be present in the LDAP search result.",
          required = false,
          type = "array",
          elements = {
            type = "string",
          }
        }},
        { realm = { description = "When authentication fails the plugin sends `WWW-Authenticate` header with `realm` attribute value.", type = "string", required = false }, },
      }
    }}
  },
  entity_checks = {
    { custom_entity_check = {
      field_sources = { "config" },
      fn = check_ldaps_tls
    }}
  }
}
