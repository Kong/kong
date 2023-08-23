local plugin_name = "konnect-application-auth"
local package_name = "kong-plugin-" .. plugin_name
local package_version = "dev"
local rockspec_revision = "0"
local dao_name = "konnect_applications"

local github_account_name = "Kong"
local github_repo_name = "kong-plugin-konnect-application-auth"
local git_checkout = package_version == "dev" and "master" or package_version


package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }
source = {
  url = "git+https://github.com/"..github_account_name.."/"..github_repo_name..".git",
  branch = git_checkout,
}


description = {
  summary = "Konnect Application Auth",
}


dependencies = {

}


build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..plugin_name..".handler"] = "kong/plugins/"..plugin_name.."/handler.lua",
    ["kong.plugins."..plugin_name..".schema"] = "kong/plugins/"..plugin_name.."/schema.lua",
    ["kong.plugins."..plugin_name..".daos"] = "kong/plugins/"..plugin_name.."/daos.lua",
    ["kong.plugins."..plugin_name..".migrations"] = "kong/plugins/"..plugin_name.."/migrations/init.lua",
    ["kong.plugins."..plugin_name..".migrations.000_base_"..dao_name] = "kong/plugins/"..plugin_name.."/migrations/000_base_"..dao_name..".lua",
    ["kong.plugins."..plugin_name..".migrations.001_consumer_group_addition"] = "kong/plugins/"..plugin_name.."/migrations/001_consumer_group_addition.lua",
  }
}
