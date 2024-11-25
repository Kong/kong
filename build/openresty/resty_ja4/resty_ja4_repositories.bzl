"""A module defining the dependency resty-ja4"""

load("@kong_bindings//:variables.bzl", "KONG_VAR")
load("//build:build_system.bzl", "git_or_local_repository")

def resty_ja4_repositories():
    git_or_local_repository(
        name = "resty_ja4",
        branch = KONG_VAR["LUA_RESTY_JA4"],
        # Since majority of Kongers are using the GIT protocol,
        # so we'd better use the same protocol instead of HTTPS
        # for private repositories.
        remote = "git@github.com:Kong/resty-ja4.git",
        build_file = "//build/openresty/resty_ja4:BUILD.resty_ja4.bazel",
    )
