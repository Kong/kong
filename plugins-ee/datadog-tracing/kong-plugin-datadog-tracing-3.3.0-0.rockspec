local plugin_name = "datadog-tracing"
local package_name = "kong-plugin-" .. plugin_name

local package_version = "3.3.0"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

description = {
  summary = "The Kong datadog-tracing plugin allows Kong gateway to be integrated with the DataDog application montoring system",
}

source = {
  url = "https://github.com/Kong/kong-ee",
  tag = "3.3.0"
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..plugin_name..".handler"] = "kong/plugins/"..plugin_name.."/handler.lua",
    ["kong.plugins."..plugin_name..".schema"] = "kong/plugins/"..plugin_name.."/schema.lua",
    ["kong.plugins."..plugin_name..".encoder"] = "kong/plugins/"..plugin_name.."/encoder.lua",
  }
}
