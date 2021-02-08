package = "kong-plugin-enterprise-ldap-auth"
version = "1.1.0-0"

source = {
  url = "https://github.com/Kong/kong-plugin-enterprise-ldap-auth",
  tag = "1.1.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Kong Enterprise LDAP Auth",
}

dependencies = {
  "lua_pack == 1.0.5",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.ldap-auth-advanced.handler"] = "kong/plugins/ldap-auth-advanced/handler.lua",
    ["kong.plugins.ldap-auth-advanced.access"] = "kong/plugins/ldap-auth-advanced/access.lua",
    ["kong.plugins.ldap-auth-advanced.schema"] = "kong/plugins/ldap-auth-advanced/schema.lua",
    ["kong.plugins.ldap-auth-advanced.ldap"] = "kong/plugins/ldap-auth-advanced/ldap.lua",
    ["kong.plugins.ldap-auth-advanced.asn1"] = "kong/plugins/ldap-auth-advanced/asn1.lua",
    ["kong.plugins.ldap-auth-advanced.cache"] = "kong/plugins/ldap-auth-advanced/cache.lua",
    ["kong.plugins.ldap-auth-advanced.groups"] = "kong/plugins/ldap-auth-advanced/groups.lua",
  }
}
