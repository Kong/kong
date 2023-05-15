local plugin_name = "xml-threat-protection"
local package_name = "kong-plugin-" .. plugin_name
local package_version = "dev"
local rockspec_revision = "0"
local github_account_name = "Kong"
local github_repo_name = package_name


package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }
source = {
  url = "git+https://github.com/"..github_account_name.."/"..github_repo_name..".git",
	branch = (package_version == "dev") and "master" or nil,
	tag = (package_version ~= "dev") and package_version or nil,
}


description = {
  summary = [[
    A Kong Gateway plugin that scans and blocks XML content that exceeds
    complexity rules as configured in the plugin.
  ]],
  homepage = "https://github.com/"..github_account_name.."/"..github_repo_name,
  license = "Kong proprietary, see your Kong Enterprise license",
}


build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..plugin_name..".handler"] = "kong/plugins/"..plugin_name.."/handler.lua",
    ["kong.plugins."..plugin_name..".schema"] = "kong/plugins/"..plugin_name.."/schema.lua",
  }
}
