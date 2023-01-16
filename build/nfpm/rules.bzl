"""
NFPM package rule.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def _nfpm_pkg_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.out)

    env = dicts.add(ctx.attr.env, KONG_VAR, ctx.configuration.default_shell_env)

    target_cpu = ctx.attr._cc_toolchain[cc_common.CcToolchainInfo].cpu
    if target_cpu == "k8" or target_cpu == "x86_64" or target_cpu == "amd64":
        target_arch = "amd64"
    elif target_cpu == "aarch64" or target_cpu == "arm64":
        target_arch = "arm64"
    else:
        fail("Unsupported platform cpu: %s" % target_cpu)
    env["ARCH"] = target_arch

    # XXX: remove the "env" from KONG_VAR which is a list
    env["OPENRESTY_PATCHES"] = ""

    nfpm_args = ctx.actions.args()
    nfpm_args.add("pkg")
    nfpm_args.add("-f", ctx.file.config.path)
    nfpm_args.add("-p", ctx.attr.packager)
    nfpm_args.add("-t", out.path)

    build_dir = ctx.files.src[0].dirname + "/" + KONG_VAR["BUILD_NAME"]

    ctx.actions.run_shell(
        inputs = ctx.files._nfpm_bin,
        mnemonic = "nFPM",
        command = "ln -sf %s nfpm-prefix; external/nfpm/nfpm $@" % build_dir,
        arguments = [nfpm_args],
        outputs = [out],
        env = env,
    )

    # TODO: fix runfiles so that it can used as a dep
    return [DefaultInfo(files = depset([out]), runfiles = ctx.runfiles(files = ctx.files.config))]

nfpm_pkg = rule(
    _nfpm_pkg_impl,
    attrs = {
        "config": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "nFPM configuration file.",
        ),
        "src": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "source directory pointing to the build artifacts",
        ),
        "packager": attr.string(
            mandatory = True,
            doc = "Packager name.",
        ),
        "env": attr.string_dict(
            doc = "Environment variables to set when running nFPM.",
        ),
        "out": attr.string(
            mandatory = True,
            doc = "Output file name.",
        ),
        # hidden attributes
        "_nfpm_bin": attr.label(
            default = "@nfpm//:all_srcs",
        ),
        "_cc_toolchain": attr.label(
            default = "@bazel_tools//tools/cpp:current_cc_toolchain",
        ),
    },
)
