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
        sha256 = "420fe35e7572f2a168d17e660ef981a589c9cbe77faa25eb34a520e1fcc032c8",
        url = "https://github.com/msgpack/msgpack-c/releases/download/" + version + "/msgpack-" + version + ".tar.gz",
    )
