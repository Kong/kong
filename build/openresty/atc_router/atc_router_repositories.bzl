"""A module defining the dependency atc-router"""

load("@kong_bindings//:variables.bzl", "KONG_VAR")
load("//build:build_system.bzl", "git_or_local_repository")

def atc_router_repositories():
    git_or_local_repository(
        name = "atc_router",
        branch = KONG_VAR["ATC_ROUTER"],
        remote = "https://github.com/Kong/atc-router",
        build_file = "//build/openresty/atc_router:BUILD.atc_router.bazel",
    )
