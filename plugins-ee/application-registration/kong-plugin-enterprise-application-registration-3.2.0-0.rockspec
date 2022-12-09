package = "kong-plugin-enterprise-application-registration"
version = "3.2.0-0"

source = {
  url = "https://github.com/kong/kong-plugin-enterprise-application-registration",
  tag = "3.2.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Applications allow registered developers on Kong Developer Portal to authenticate against a Gateway Service. Dev Portal admins can selectively admit access to Services using the Application Registration plugin.",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.application-registration.handler"] = "kong/plugins/application-registration/handler.lua",
    ["kong.plugins.application-registration.schema"]  = "kong/plugins/application-registration/schema.lua",
    ["kong.plugins.application-registration.api"]  = "kong/plugins/application-registration/api.lua",
  }
}
