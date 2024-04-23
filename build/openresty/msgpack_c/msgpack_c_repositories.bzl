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
        sha256 = "a349cd9af28add2334c7009e331335af4a5b97d8558b2e9804d05f3b33d97925",
        url = "https://github.com/msgpack/msgpack-c/releases/download/" + version + "/msgpack-" + version + ".tar.gz",
    )
