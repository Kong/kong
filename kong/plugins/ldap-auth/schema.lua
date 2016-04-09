return {
fields = {
    ldap_host = {required = true, type = "string"},
    ldap_port = {required = true, type = "number"},
    start_tls = {required = true, type = "boolean", default = false},
    verify_ldap_host = {required = true, type = "boolean", default = false},
    base_dn = {required = true, type = "string"},
    attribute = {required = true, type = "string"},
    cache_ttl = {required = true, type = "number", default = 60},
    hide_credentials = {type = "boolean", default = false},
    timeout = {type = "number", default = 10000},
    keepalive = {type = "number", default = 60000},
  }
}
