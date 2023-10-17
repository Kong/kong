"""A module defining the third party dependency curl and its dependencies"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive", "http_file")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def curl_repositories():
    """Defines the curl repository"""

    version = KONG_VAR["CURL"]
    prefix = "curl-" + version
    tag = prefix.replace(".", "_")
    tarball = prefix + ".tar.gz"

    maybe(
        http_archive,
        name = "curl",
        urls = [
            "https://curl.se/download/" + tarball,
            "https://github.com/curl/curl/releases/download/%s/%s" % (tag, tarball),
            "https://mirror.bazel.build/curl.haxx.se/download/" + tarball,
        ],
        type = "tar.gz",
        sha256 = "816e41809c043ff285e8c0f06a75a1fa250211bbfb2dc0a037eeef39f1a9e427",
        strip_prefix = prefix,
        build_file = "//build/curl:BUILD.curl.bazel",
    )

    version = KONG_VAR["NGHTTP2"]
    prefix = "nghttp2-" + version
    tag = "v" + version
    tarball = prefix + ".tar.gz"

    maybe(
        http_archive,
        name = "nghttp2",
        urls = [
            "https://github.com/nghttp2/nghttp2/releases/download/%s/%s" % (tag, tarball),
        ],
        type = "tar.gz",
        sha256 = "1e3258453784d3b7e6cc48d0be087b168f8360b5d588c66bfeda05d07ad39ffd",
        strip_prefix = prefix,
        build_file = Label("//build/curl:BUILD.nghttp2.bazel"),
    )

    version = KONG_VAR["CA_CERTS"]

    maybe(
        http_file,
        name = "cacerts-bundle",
        urls = [
            "https://curl.se/ca/cacert-%s.pem" % version,
        ],
        sha256 = "23c2469e2a568362a62eecf1b49ed90a15621e6fa30e29947ded3436422de9b9",
    )
