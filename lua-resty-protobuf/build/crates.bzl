"""Setup Crates repostories """

load("@resty_protobuf_crate_index//:defs.bzl", "crate_repositories")

def resty_protobuf_crates():
    crate_repositories()
