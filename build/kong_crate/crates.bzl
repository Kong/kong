"""Setup Crates repostories """

load("@atc_router_crate_index//:defs.bzl", atc_router_crate_repositories = "crate_repositories")

def kong_crates():
    atc_router_crate_repositories()
