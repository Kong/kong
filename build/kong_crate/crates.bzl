"""Setup Crates repostories """

load("@atc_router_crate_index//:defs.bzl", atc_router_crate_repositories = "crate_repositories")
load("@json_threat_protection_crate_index//:defs.bzl", json_threat_protection_crate_repositories = "crate_repositories")
load("@jsonschema_crate_index//:defs.bzl", jsonschema_crate_repositories = "crate_repositories")

def kong_crates():
    atc_router_crate_repositories()
    json_threat_protection_crate_repositories()
    jsonschema_crate_repositories()
