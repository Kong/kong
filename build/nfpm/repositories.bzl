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
        ["linux", "x86_64", "4c63031ddbef198e21c8561c438dde4c93c3457ffdc868d7d28fa670e0cc14e5"],
        ["linux", "arm64", "2af1717cc9d5dcad5a7e42301dabc538acf5d12ce9ee39956c66f30215311069"],
        ["Darwin", "x86_64", "fb3b8ab5595117f621c69cc51db71d481fbe733fa3c35500e1b64319dc8fd5b4"],
        ["Darwin", "arm64", "9ca3ac6e0c4139a9de214f78040d1d11dd221496471696cc8ab5d357850ccc54"],
    ]
    for name, arch, sha in npfm_matrix:
        http_archive(
            name = "nfpm_%s_%s" % (name, arch),
            url = "https://github.com/goreleaser/nfpm/releases/download/v2.23.0/nfpm_2.23.0_%s_%s.tar.gz" % (name, arch),
            sha256 = sha,
            build_file = "//build/nfpm:BUILD.bazel",
        )

    nfpm_release_select(
        name = "nfpm",
        build_file = "//build/nfpm:BUILD.bazel",
    )
