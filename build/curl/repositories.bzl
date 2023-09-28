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
            "https://mirror.bazel.build/curl.haxx.se/download/" + tarball,
            "https://curl.se/download/" + tarball,
            "https://github.com/curl/curl/releases/download/%s/%s" % (tag, tarball),
        ],
        type = "tar.gz",
        sha256 = "d3a19aeea301085a56c32bc0f7d924a818a7893af253e41505d1e26d7db8e95a",
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
        sha256 = "eb00ded354db1159dcccabc11b0aaeac893b7c9b154f8187e4598c4b8f3446b5",
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
