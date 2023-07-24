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
        ["linux", "x86_64", "6dd3b07d4d6ee373baea5b5fca179ebf78dec38c9a55392bae34040e596e4de7"],
        ["linux", "arm64", "e6487dca9d9e9b1781fe7fa0a3d844e70cf12d92f3b5fc0c4ff771aa776b05ca"],
        ["Darwin", "x86_64", "19954ef8e6bfa0607efccd0a97452b6d571830665bd76a2f9957413f93f9d8cd"],
        ["Darwin", "arm64", "9fd82cda017cdfd49b010199a2eed966d0a645734d9a6bf932c4ef82c8c12c96"],
    ]
    for name, arch, sha in npfm_matrix:
        http_archive(
            name = "nfpm_%s_%s" % (name, arch),
            url = "https://github.com/goreleaser/nfpm/releases/download/v2.31.0/nfpm_2.31.0_%s_%s.tar.gz" % (name, arch),
            sha256 = sha,
            build_file = "//build/nfpm:BUILD.bazel",
        )

    nfpm_release_select(
        name = "nfpm",
        build_file = "//build/nfpm:BUILD.bazel",
    )
