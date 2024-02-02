"""A module defining the third party dependency msgpack-c"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def msgpack_c_repositories():
    version = KONG_VAR["MSGPACK_C"]

    maybe(
        http_archive,
        name = "msgpack_c",
        build_file = "//build/openresty/msgpack_c:BUILD.msgpack_c.bazel",
        strip_prefix = "msgpack-" + version,
        sha256 = "3654f5e2c652dc52e0a993e270bb57d5702b262703f03771c152bba51602aeba",
        url = "https://github.com/msgpack/msgpack-c/releases/download/" + version + "/msgpack-" + version + ".tar.gz",
    )
