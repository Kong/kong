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
        sha256 = "f91249c87f68ea00cf27c44fdfa5a78423e41e71b7d408e5901a9896d905c495",
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
        sha256 = "aa7594c846e56a22fbf3d6e260e472268808d3b49d5e0ed339f589e9cc9d484c",
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
        sha256 = "1794c1d4f7055b7d02c2170337b61b48a2ef6c90d77e95444fd2596f4cac609f",
    )
