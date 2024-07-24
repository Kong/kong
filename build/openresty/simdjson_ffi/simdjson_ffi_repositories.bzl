"""A module defining the dependency lua-resty-simdjson"""

load("//build:build_system.bzl", "git_or_local_repository")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def simdjson_ffi_repositories():
    git_or_local_repository(
        name = "simdjson_ffi",
        branch = KONG_VAR["LUA_RESTY_SIMDJSON"],
        remote = "https://github.com/Kong/lua-resty-simdjson",
    )
