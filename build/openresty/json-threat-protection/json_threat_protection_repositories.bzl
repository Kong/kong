"""A module defining the dependency lua-resty-json-threat-protection"""

load("@kong_bindings//:variables.bzl", "KONG_VAR")
load("//build:build_system.bzl", "git_or_local_repository")

def json_threat_protection_repositories():
    git_or_local_repository(
        name = "json_threat_protection",
        branch = KONG_VAR["JSON_THREAT_PROTECTION"],
        # Since majority of Kongers are using the GIT protocol,
        # so we'd better use the same protocol instead of HTTPS
        # for private repositories.
        remote = "git@github.com:Kong/json-threat-protection.rs.git",
    )
