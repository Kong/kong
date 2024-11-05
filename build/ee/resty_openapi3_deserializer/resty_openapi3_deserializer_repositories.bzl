"""A module defining the dependency lua-resty-openapi3-deserializer"""

load("@kong_bindings//:variables.bzl", "KONG_VAR")
load("//build:build_system.bzl", "git_or_local_repository")

def resty_openapi3_deserializer_repositories():
    git_or_local_repository(
        name = "resty_openapi3_deserializer",
        branch = KONG_VAR["RESTY_OPENAPI3_DESERIALIZER"],
        # Since majority of Kongers are using the GIT protocol,
        # so we'd better use the same protocol instead of HTTPS
        # for private repositories.
        remote = "git@github.com:Kong/lua-resty-openapi3-deserializer.git",
        build_file = "//build/ee/resty_openapi3_deserializer:BUILD.resty_openapi3_deserializer.bazel",
    )
