package = "kong-plugin-enterprise-degraphql"
version = "0.1.2-1"

supported_platforms = {"linux", "macosx"}
source = {
  url = "http://github.com/Kong/kong-plugin.git",
  tag = "0.1.2"
}

description = {
  summary = "Kong is a scalable and customizable API Management Layer built on top of Nginx.",
  homepage = "http://getkong.org",
  license = "Apache 2.0"
}

dependencies = {

}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.degraphql.api"] = "kong/plugins/degraphql/api.lua",
    ["kong.plugins.degraphql.daos"] = "kong/plugins/degraphql/daos.lua",
    ["kong.plugins.degraphql.handler"] = "kong/plugins/degraphql/handler.lua",
    ["kong.plugins.degraphql.schema"] = "kong/plugins/degraphql/schema.lua",
    ["kong.plugins.degraphql.migrations"] = "kong/plugins/degraphql/migrations/init.lua",
    ["kong.plugins.degraphql.migrations.000_base"] = "kong/plugins/degraphql/migrations/000_base.lua",
  }
}
