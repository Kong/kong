"""
Global varibles
"""

def _load_vars(ctx):
    # Read env from .requirements
    requirements = ctx.read(Label("@kong//:.requirements"))
    content = ctx.execute(["bash", "-c", "echo '%s' | " % requirements +
                                         """grep -E '^(\\w*)=(.+)$' | sed -E 's/^(.*)=(.*)$/"\\1": "\\2",/'"""]).stdout
    content = content.replace('""', '"')

    # Workspace path
    workspace_path = "%s" % ctx.path(Label("@//:WORKSPACE")).dirname
    content += '"WORKSPACE_PATH": "%s",\n' % workspace_path

    # Local env
    # Temporarily fix for https://github.com/bazelbuild/bazel/issues/14693#issuecomment-1079006291
    for key in [
        "PATH",
        # above should not be needed
        "GITHUB_TOKEN",
        "RPM_SIGNING_KEY_FILE",
        "NFPM_RPM_PASSPHRASE",
    ]:
        value = ctx.os.environ.get(key, "")
        if value:
            content += '"%s": "%s",\n' % (key, value)

    build_name = ctx.os.environ.get("BUILD_NAME", "")
    content += '"BUILD_NAME": "%s",\n' % build_name

    build_destdir = workspace_path + "/bazel-bin/build/" + build_name
    content += '"BUILD_DESTDIR": "%s",\n' % build_destdir

    install_destdir = ctx.os.environ.get("INSTALL_DESTDIR", "MANAGED")
    if install_destdir == "MANAGED":
        install_destdir = build_destdir
    content += '"INSTALL_DESTDIR": "%s",\n' % install_destdir

    # Kong Version
    # TODO: this may not change after a bazel clean if cache exists
    kong_version = ctx.execute(["bash", "scripts/grep-kong-version.sh"], working_directory = workspace_path).stdout
    content += '"KONG_VERSION": "%s",' % kong_version.strip()

    nproc = ctx.execute(["nproc"]).stdout.strip()
    content += '"%s": "%s",' % ("NPROC", nproc)

    macos_target = ""
    if ctx.os.name == "mac os x":
        macos_target = ctx.execute(["sw_vers", "-productVersion"]).stdout.strip()
    content += '"MACOSX_DEPLOYMENT_TARGET": "%s",' % macos_target

    # convert them into a list of labels relative to the workspace root
    # TODO: this may not change after a bazel clean if cache exists
    patches = [
        '"@kong//:%s"' % str(p).replace(workspace_path, "").lstrip("/")
        for p in ctx.path(workspace_path + "/build/openresty/patches").readdir()
    ]

    content += '"OPENRESTY_PATCHES": [%s],' % (", ".join(patches))

    ctx.file("BUILD.bazel", "")
    ctx.file("variables.bzl", "KONG_VAR = {\n" + content + "\n}")

def _load_bindings_impl(ctx):
    _load_vars(ctx)

load_bindings = repository_rule(
    implementation = _load_bindings_impl,
    # force "fetch"/invalidation of this repository every time it runs
    # so that environ vars, patches and kong version is up to date
    # see https://blog.bazel.build/2017/02/22/repository-invalidation.html
    local = True,
    environ = [
        "BUILD_NAME",
        "INSTALL_DESTDIR",
        "RPM_SIGNING_KEY_FILE",
        "NFPM_RPM_PASSPHRASE",
    ],
)
