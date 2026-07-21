"""Setup Crates repostories """

load("@atc_router_crate_index//:defs.bzl", atc_router_crate_repositories = "crate_repositories")
load("@rusty_cli_crate_index//:defs.bzl", rusty_cli_crate_repositories = "crate_repositories")

def kong_crates():
    atc_router_crate_repositories()
    rusty_cli_crate_repositories()
