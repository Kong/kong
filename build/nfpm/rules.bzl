"""
NFPM package rule.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def _nfpm_pkg_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.out)

    env = dicts.add(ctx.attr.env, KONG_VAR, ctx.configuration.default_shell_env)

    nfpm_args = ctx.actions.args()
    nfpm_args.add("pkg")
    nfpm_args.add("-f", ctx.attr.config)
    nfpm_args.add("-p", ctx.attr.packager)
    nfpm_args.add("-t", out.path)

    ctx.actions.run(
        inputs = ctx.files.srcs,
        mnemonic = "nFPM",
        executable = "../../external/nfpm/nfpm",
        arguments = [nfpm_args],
        outputs = [out],
        env = env,
    )

    return [DefaultInfo(files = depset([out]))]

nfpm_pkg = rule(
    _nfpm_pkg_impl,
    attrs = {
        "srcs": attr.label_list(
            default = ["@nfpm//:srcs"],
        ),
        "config": attr.string(
            mandatory = True,
            doc = "nFPM configuration file.",
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
    },
)
