package = "kong-plugin-mocking"
version = "dev-0"

local pluginName = package:match("^kong%-plugin%-(.+)$")  -- "mocking"

supported_platforms = {"linux", "macosx"}
source = {
  url = "http://github.com/Kong/kong-plugin-mocking.git",
  tag = "dev"
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
    ["kong.plugins."..pluginName..".handler"] = "kong/plugins/"..pluginName.."/handler.lua",
    ["kong.plugins."..pluginName..".schema"] = "kong/plugins/"..pluginName.."/schema.lua",
    ["kong.plugins."..pluginName..".mime_parse"] = "kong/plugins/"..pluginName.."/mime_parse.lua",
    ["kong.plugins."..pluginName..".constants"] = "kong/plugins/"..pluginName.."/constants.lua",

    ["kong.plugins."..pluginName..".jsonschema-mocker.type.boolean"] = "kong/plugins/"..pluginName.."/jsonschema-mocker/type/boolean.lua",
    ["kong.plugins."..pluginName..".jsonschema-mocker.type.integer"] = "kong/plugins/"..pluginName.."/jsonschema-mocker/type/integer.lua",
    ["kong.plugins."..pluginName..".jsonschema-mocker.type.number"] = "kong/plugins/"..pluginName.."/jsonschema-mocker/type/number.lua",
    ["kong.plugins."..pluginName..".jsonschema-mocker.type.string"] = "kong/plugins/"..pluginName.."/jsonschema-mocker/type/string.lua",
    ["kong.plugins."..pluginName..".jsonschema-mocker.constants"] = "kong/plugins/"..pluginName.."/jsonschema-mocker/constants.lua",
    ["kong.plugins."..pluginName..".jsonschema-mocker.mocker"] = "kong/plugins/"..pluginName.."/jsonschema-mocker/mocker.lua",
  }
}
