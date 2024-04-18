package = "kong-plugin-enterprise-ai-azure-content-safety"
version = "dev-0"

source = {
  url = "",
  tag = "dev"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Allows checking and auditing of AI-Proxy plugin messages, using Azure Cognitive Services, before proxying to upstream large-language model.",
  homepage = "https://docs.konghq.com/hub/kong-inc/ai-azure-content-safety/",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.ai-azure-content-safety.handler"] = "kong/plugins/ai-azure-content-safety/handler.lua",
    ["kong.plugins.ai-azure-content-safety.schema"]  = "kong/plugins/ai-azure-content-safety/schema.lua",
  }
}
