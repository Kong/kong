"""Setup Crates repostories """

load("@kong_crate_index//:defs.bzl", "crate_repositories")

def kong_crates():
    crate_repositories()
