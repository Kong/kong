"""A module defining the dependency lua-resty-json-threat-protection"""

load("@kong_bindings//:variables.bzl", "KONG_VAR")

def json_threat_protection_repositories():
    native.local_repository(
        name = "json_threat_protection",
        path = "distribution/lua-resty-json-threat-protection",
    )
