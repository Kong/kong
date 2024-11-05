"""A module defining the dependency kong-gql"""

load("@kong_bindings//:variables.bzl", "KONG_VAR")
load("//build:build_system.bzl", "git_or_local_repository")

def kong_gql_repositories():
    git_or_local_repository(
        name = "kong_gql",
        branch = KONG_VAR["KONG_GQL"],
        # Since majority of Kongers are using the GIT protocol,
        # so we'd better use the same protocol instead of HTTPS
        # for private repositories.
        remote = "git@github.com:Kong/kong-gql.git",
        build_file = "//build/ee/kong_gql:BUILD.kong-gql.bazel",
    )
