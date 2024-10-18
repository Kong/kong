"""A module defining the dependency lua-resty-jsonschema-rs"""

load("@kong_bindings//:variables.bzl", "KONG_VAR")
load("//build:build_system.bzl", "git_or_local_repository")

def jsonschema_repositories():
    git_or_local_repository(
        name = "jsonschema",
        branch = KONG_VAR["RESTY_JSONSCHEMA_RS"],
        # Since majority of Kongers are using the GIT protocol,
        # so we'd better use the same protocol instead of HTTPS
        # for private repositories.
        remote = "git@github.com:Kong/lua-resty-jsonschema-rs.git",
        build_file = "//build/openresty/jsonschema:BUILD.jsonschema.bazel",
    )
