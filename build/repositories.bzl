"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")
load("//build:build_system.bzl", "git_or_local_repository", "github_release")
load("//build/cross_deps:repositories.bzl", "cross_deps_repositories")
load("//build/libexpat:repositories.bzl", "libexpat_repositories")
load("//build/luarocks:luarocks_repositories.bzl", "luarocks_repositories")
load("//build/toolchain:bindings.bzl", "load_bindings")

_SRCS_BUILD_FILE_CONTENT = """
filegroup(
    name = "all_srcs",
    srcs = glob(["**"]),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "lualib_srcs",
    srcs = glob(["lualib/**/*.lua", "lib/**/*.lua"]),
    visibility = ["//visibility:public"],
)
"""

_DIST_BUILD_FILE_CONTENT = """
filegroup(
    name = "dist",
    srcs = glob(["dist/**"]),
    visibility = ["//visibility:public"],
)
"""

def github_cli_repositories():
    """Defines the github cli repositories"""

    gh_matrix = [
        ["linux", "amd64", "tar.gz", "7f9795b3ce99351a1bfc6ea3b09b7363cb1eccca19978a046bcb477839efab82"],
        ["linux", "arm64", "tar.gz", "115e1a18695fcc2e060711207f0c297f1cca8b76dd1d9cd0cf071f69ccac7422"],
        ["macOS", "amd64", "zip", "d18acd3874c9b914e0631c308f8e2609bd45456272bacfa70221c46c76c635f6"],
        ["macOS", "arm64", "zip", "85fced36325e212410d0eea97970251852b317d49d6d72fd6156e522f2896bc5"],
    ]
    for name, arch, type, sha in gh_matrix:
        http_archive(
            name = "gh_%s_%s" % (name, arch),
            url = "https://github.com/cli/cli/releases/download/v2.50.0/gh_2.50.0_%s_%s.%s" % (name, arch, type),
            strip_prefix = "gh_2.50.0_%s_%s" % (name, arch),
            sha256 = sha,
            build_file_content = _SRCS_BUILD_FILE_CONTENT,
        )

def kong_github_repositories():
    maybe(
        github_release,
        name = "kong_admin_gui",
        repo = "kong/kong-manager",
        tag = KONG_VAR["KONG_MANAGER"],
        pattern = "release.tar.gz",
        build_file_content = _DIST_BUILD_FILE_CONTENT,
    )

def protoc_repositories():
    http_archive(
        name = "protoc",
        url = "https://github.com/protocolbuffers/protobuf/releases/download/v3.19.0/protoc-3.19.0-linux-x86_64.zip",
        sha256 = "2994b7256f7416b90ad831dbf76a27c0934386deb514587109f39141f2636f37",
        build_file_content = """
filegroup(
    name = "include",
    srcs = glob(["include/google/**"]),
    visibility = ["//visibility:public"],
)""",
    )

def kong_resty_websocket_repositories():
    git_or_local_repository(
        name = "lua-resty-websocket",
        branch = KONG_VAR["LUA_RESTY_WEBSOCKET"],
        remote = "https://github.com/Kong/lua-resty-websocket",
        build_file_content = _SRCS_BUILD_FILE_CONTENT,
    )

def build_repositories():
    load_bindings(name = "toolchain_bindings")

    libexpat_repositories()
    luarocks_repositories()

    kong_resty_websocket_repositories()
    github_cli_repositories()
    kong_github_repositories()

    protoc_repositories()

    cross_deps_repositories()
