"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def _nfpm_release_select_impl(ctx):
    if ctx.attr.build_file:
        ctx.file("BUILD.bazel", ctx.read(ctx.attr.build_file))
    elif ctx.attr.build_file_content:
        ctx.file("BUILD.bazel", ctx.attr.build_file_content)

    os_name = ctx.os.name
    os_arch = ctx.os.arch

    if os_arch == "aarch64":
        os_arch = "arm64"
    elif os_arch == "amd64":
        os_arch = "x86_64"
    else:
        fail("Unsupported arch %s" % os_arch)

    if os_name == "mac os x":
        os_name = "Darwin"
    elif os_name != "linux":
        fail("Unsupported OS %s" % os_name)

    nfpm_bin = "%s" % ctx.path(Label("@nfpm_%s_%s//:nfpm" % (os_name, os_arch)))
    ctx.symlink(nfpm_bin, "nfpm")

nfpm_release_select = repository_rule(
    implementation = _nfpm_release_select_impl,
    attrs = {
        "build_file": attr.label(allow_single_file = True),
        "build_file_content": attr.string(),
    },
)

def nfpm_repositories():
    npfm_matrix = [
        ["linux", "x86_64", "3e1fe85c9a224a221c64cf72fc19e7cd6a0a51a5c4f4b336e3b8eccd417116a3"],
        ["linux", "arm64", "df8f272195b7ddb09af9575673a9b8111f9eb7529cdd0a3fac4d44b52513a1e1"],
        ["Darwin", "x86_64", "0213fa5d5af6f209d953c963103f9b6aec8a0e89d4bf0ab3d531f5f8b20b8eeb"],
        ["Darwin", "arm64", "5162ce5a59fe8d3b511583cb604c34d08bd2bcced87d9159c7005fc35287b9cd"],
    ]
    for name, arch, sha in npfm_matrix:
        http_archive(
            name = "nfpm_%s_%s" % (name, arch),
            url = "https://github.com/goreleaser/nfpm/releases/download/v2.37.1/nfpm_2.37.1_%s_%s.tar.gz" % (name, arch),
            sha256 = sha,
            build_file = "//build/nfpm:BUILD.bazel",
        )

    nfpm_release_select(
        name = "nfpm",
        build_file = "//build/nfpm:BUILD.bazel",
    )
