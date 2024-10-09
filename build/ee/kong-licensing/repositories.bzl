"""A module defining the third party dependency OpenResty"""

load("@kong_bindings//:variables.bzl", "KONG_VAR")
load("//build:build_system.bzl", "git_or_local_repository")

def kong_licensing_repositories():
    git_or_local_repository(
        name = "kong-licensing",
        branch = KONG_VAR["KONG_LICENSING"],
        # Since majority of Kongers are using the GIT protocol,
        # so we'd better use the same protocol instead of HTTPS
        # for private repositories.
        remote = "git@github.com:Kong/kong-licensing.git",
        strip_prefix = "lib",
        build_file = "//build/ee/kong-licensing:BUILD.kong-licensing.bazel",
    )
