"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")
load("//build/luarocks:luarocks_repositories.bzl", "luarocks_repositories")
load("//build/cross_deps:repositories.bzl", "cross_deps_repositories")
load("//build:build_system.bzl", "github_release")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

_SRCS_BUILD_FILE_CONTENT = """
filegroup(
    name = "all_srcs",
    srcs = glob(["**"]),
    visibility = ["//visibility:public"],
)
"""

_DIST_BUILD_FILE_CONTENT = """
filegroup(
    name = "dist_files",
    srcs = ["dist"],
    visibility = ["//visibility:public"],
)
"""

def github_cli_repositories():
    """Defines the github cli repositories"""

    gh_matrix = [
        ["linux", "amd64", "tar.gz", "5aee45bd42a27f5be309373c326e45cbcc7f04591b1798581a3094af767225b7"],
        ["linux", "arm64", "tar.gz", "3ef741bcc1ae8bb975adb79a78e26ab7f18a246197f193aaa8cb5c3bdc373a3f"],
        ["macOS", "amd64", "zip", "6b91c446586935de0e9df82da58309b2d1b83061cfcd4cc173124270f1277ca7"],
        ["macOS", "arm64", "zip", "32a71652367f3cf664894456e4c4f655faa95964d71cc3a449fbf64bdce1fff1"],
    ]
    for name, arch, type, sha in gh_matrix:
        http_archive(
            name = "gh_%s_%s" % (name, arch),
            url = "https://github.com/cli/cli/releases/download/v2.30.0/gh_2.30.0_%s_%s.%s" % (name, arch, type),
            strip_prefix = "gh_2.30.0_%s_%s" % (name, arch),
            sha256 = sha,
            build_file_content = _SRCS_BUILD_FILE_CONTENT,
        )

def protoc_repositories():
    http_archive(
        name = "protoc",
        url = "https://github.com/protocolbuffers/protobuf/releases/download/v3.19.0/protoc-3.19.0-linux-x86_64.zip",
        sha256 = "2994b7256f7416b90ad831dbf76a27c0934386deb514587109f39141f2636f37",
        build_file_content = """
filegroup(
    name = "all_srcs",
    srcs = ["include"],
    visibility = ["//visibility:public"],
)""",
    )

def kong_resty_websocket_repositories():
    new_git_repository(
        name = "lua-resty-websocket",
        branch = KONG_VAR["LUA_RESTY_WEBSOCKET"],
        remote = "https://github.com/Kong/lua-resty-websocket",
        build_file_content = _SRCS_BUILD_FILE_CONTENT,
    )

def build_repositories():
    luarocks_repositories()

    github_cli_repositories()

    protoc_repositories()

    cross_deps_repositories()
