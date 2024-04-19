"""A module defining the dependency lua-resty-jsonschema-rs"""

load("@kong_bindings//:variables.bzl", "KONG_VAR")

def jsonschema_repositories():
    native.local_repository(
        name = "jsonschema",
        path = "distribution/lua-resty-jsonschema-rs",
    )
