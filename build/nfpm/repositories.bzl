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
        ["linux", "x86_64", "e763ba82cc844c0084b66a386ccaff801b3e655a5bb20d222c3329880ff2e958"],
        ["linux", "arm64", "985496acee0bc6d7fdb2a41f94208120a7cf025e37446286c4aaa0988a18f268"],
        ["Darwin", "x86_64", "9b891d9386609dbd91d5aa76bde61342bc0f48514b8759956489fe2eaf6622b7"],
        ["Darwin", "arm64", "5d192dd168c3f9f507db977d34c888b9f7c07331a5ba4099750809de3d0d010a"],
    ]
    for name, arch, sha in npfm_matrix:
        http_archive(
            name = "nfpm_%s_%s" % (name, arch),
            url = "https://github.com/goreleaser/nfpm/releases/download/v2.41.2/nfpm_2.41.2_%s_%s.tar.gz" % (name, arch),
            sha256 = sha,
            build_file = "//build/nfpm:BUILD.bazel",
        )

    nfpm_release_select(
        name = "nfpm",
        build_file = "//build/nfpm:BUILD.bazel",
    )
