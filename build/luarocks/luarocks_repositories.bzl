"""A module defining the third party dependency luarocks"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//build:build_system.bzl", "github_release")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def luarocks_repositories():
    version = KONG_VAR["LUAROCKS"]

    http_archive(
        name = "luarocks",
        build_file = "//build/luarocks:BUILD.luarocks.bazel",
        strip_prefix = "luarocks-" + version,
        sha256 = "bca6e4ecc02c203e070acdb5f586045d45c078896f6236eb46aa33ccd9b94edb",
        urls = [
            "https://luarocks.org/releases/luarocks-" + version + ".tar.gz",
        ],
    )

    kongrocks_tag_without_v = KONG_VAR["KONGROCKS"].lstrip("v")
    github_release(
        name = "kongrocks",
        repo = "kong/kongrocks",
        tag = KONG_VAR["KONGROCKS"],
        archive = "zip",
        strip_prefix = "kongrocks-" + kongrocks_tag_without_v,
        skip_add_copyright_header = True,
        build_file_content = """
filegroup(
    name = "all_srcs",
    srcs = glob(["**"]),
    visibility = ["//visibility:public"]
)
""",
    )
