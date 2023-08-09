"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")
load("//build/luarocks:luarocks_repositories.bzl", "luarocks_repositories")
load("//build/cross_deps:repositories.bzl", "cross_deps_repositories")
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

def kong_github_repositories():
    maybe(
        github_release,
        name = "kong_admin_gui",
        repo = "kong/kong-manager",
        tag = KONG_VAR["KONG_MANAGER"],
        pattern = "release.tar.gz",
        build_file_content = _DIST_BUILD_FILE_CONTENT,
    )

def _copyright_header(ctx):
    paths = ctx.execute(["find", ctx.path("."), "-type", "f"]).stdout.split("\n")

    copyright_content = ctx.read(ctx.path(Label("@kong//:distribution/COPYRIGHT-HEADER"))).replace("--", " ")
    copyright_content_js = "/*\n" + copyright_content + "*/\n\n"
    copyright_content_html = "<!--\n" + copyright_content + "-->\n\n"
    for path in paths:
        if path.endswith(".js") or path.endswith(".map") or path.endswith(".css"):
            content = ctx.read(path)
            if not content.startswith(copyright_content_js):
                # the default enabled |legacy_utf8| leads to a double-encoded utf-8
                # while writing utf-8 content read by |ctx.read|, let's disable it
                ctx.file(path, copyright_content_js + content, legacy_utf8 = False)

        elif path.endswith(".html"):
            content = ctx.read(path)
            if not content.startswith(copyright_content_html):
                # the default enabled |legacy_utf8| leads to a double-encoded utf-8
                # while writing utf-8 content read by |ctx.read|, let's disable it
                ctx.file(path, copyright_content_html + content, legacy_utf8 = False)

def _github_release_impl(ctx):
    ctx.file("WORKSPACE", "workspace(name = \"%s\")\n" % ctx.name)

    if ctx.attr.build_file:
        ctx.file("BUILD.bazel", ctx.read(ctx.attr.build_file))
    elif ctx.attr.build_file_content:
        ctx.file("BUILD.bazel", ctx.attr.build_file_content)

    os_name = ctx.os.name
    os_arch = ctx.os.arch

    if os_arch == "aarch64":
        os_arch = "arm64"
    elif os_arch == "x86_64":
        os_arch = "amd64"
    elif os_arch != "amd64":
        fail("Unsupported arch %s" % os_arch)

    if os_name == "mac os x":
        os_name = "macOS"
    elif os_name != "linux":
        fail("Unsupported OS %s" % os_name)

    gh_bin = "%s" % ctx.path(Label("@gh_%s_%s//:bin/gh" % (os_name, os_arch)))
    ret = ctx.execute([gh_bin, "release", "download", ctx.attr.tag, "-p", ctx.attr.pattern, "-R", ctx.attr.repo])

    if ret.return_code != 0:
        gh_token_set = "GITHUB_TOKEN is set, is it valid?"
        if not ctx.os.environ.get("GITHUB_TOKEN", ""):
            gh_token_set = "GITHUB_TOKEN is not set, is this a private repo?"
        fail("Failed to download release (%s): %s, exit: %d" % (gh_token_set, ret.stderr, ret.return_code))

    ctx.extract(ctx.attr.pattern)

github_release = repository_rule(
    implementation = _github_release_impl,
    attrs = {
        "tag": attr.string(mandatory = True),
        "pattern": attr.string(mandatory = True),
        "repo": attr.string(mandatory = True),
        "build_file": attr.label(allow_single_file = True),
        "build_file_content": attr.string(),
    },
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

    kong_resty_websocket_repositories()
    github_cli_repositories()
    kong_github_repositories()

    protoc_repositories()

    cross_deps_repositories()
