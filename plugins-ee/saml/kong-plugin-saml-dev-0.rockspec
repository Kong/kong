package = "kong-plugin-saml"
version = "dev-0"

source = {
  url = "",
  tag = "dev"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "SAML plugin for Kong",
  license = "Apache 2.0",
}

dependencies = {
  "datafile == 0.10-1",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.saml.handler"] = "kong/plugins/saml/handler.lua",
    ["kong.plugins.saml.schema"] = "kong/plugins/saml/schema.lua",
    ["kong.plugins.saml.log"] = "kong/plugins/saml/log.lua",
    ["kong.plugins.saml.saml"] = "kong/plugins/saml/saml.lua",
    ["kong.plugins.saml.sessions"] = "kong/plugins/saml/sessions.lua",
    ["kong.plugins.saml.consumers"] = "kong/plugins/saml/consumers.lua",
    ["kong.plugins.saml.utils.evp"] = "kong/plugins/saml/utils/evp.lua",
    ["kong.plugins.saml.utils.helpers"] = "kong/plugins/saml/utils/helpers.lua",
    ["kong.plugins.saml.utils.canon"] = "kong/plugins/saml/utils/canon.lua",
    ["kong.plugins.saml.utils.xslt"] = "kong/plugins/saml/utils/xslt.lua",
    ["kong.plugins.saml.utils.xpath"] = "kong/plugins/saml/utils/xpath.lua",
    ["kong.plugins.saml.utils.crypt"] = "kong/plugins/saml/utils/crypt.lua",
    ["kong.plugins.saml.utils.timestamp"] = "kong/plugins/saml/utils/timestamp.lua",
    ["kong.plugins.saml.utils.xmlcatalog"] = "kong/plugins/saml/utils/xmlcatalog.lua",
    ["kong.plugins.saml.utils.xmlschema"] = "kong/plugins/saml/utils/xmlschema.lua",
  },
  copy_directories = {
    "xml"
  },
}
