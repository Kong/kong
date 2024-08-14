local package_version = "0.1.0"
local rockspec_revision = "1"

package = "kong-plugin-enterprise-upstream-oauth"
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }
source = {
  url = "git+https://github.com/KongHQ-CX/kong-plugin-enterprise-upstream-oauth.git",
  branch = "main",
}

description = {
  summary    = "Kong Enterprise OAuth Upstream Plugin.",
  detailed   = "Enables Kong to use OAuth 2.0 with the upstream service",
  license    = "Apache 2.0",
  maintainer = "Sam Gardner-Dell <sam.gardnerdell@konghq.com>",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.upstream-oauth.handler"] = "kong/plugins/upstream-oauth/handler.lua",
    ["kong.plugins.upstream-oauth.schema"] = "kong/plugins/upstream-oauth/schema.lua",
    ["kong.plugins.upstream-oauth.cache"] = "kong/plugins/upstream-oauth/cache/init.lua",
    ["kong.plugins.upstream-oauth.cache.constants"] = "kong/plugins/upstream-oauth/cache/constants.lua",
    ["kong.plugins.upstream-oauth.cache.strategies.memory"] = "kong/plugins/upstream-oauth/cache/strategies/memory.lua",
    ["kong.plugins.upstream-oauth.cache.strategies.redis"] = "kong/plugins/upstream-oauth/cache/strategies/redis.lua",
    ["kong.plugins.upstream-oauth.oauth-client"] = "kong/plugins/upstream-oauth/oauth-client/init.lua",
    ["kong.plugins.upstream-oauth.oauth-client.constants"] = "kong/plugins/upstream-oauth/oauth-client/constants.lua",
    ["kong.plugins.upstream-oauth.oauth-client.util"] = "kong/plugins/upstream-oauth/oauth-client/util.lua",
  }
}
