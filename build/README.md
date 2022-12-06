# Build

This directory contains the build system for the project.
The build system is designed to be used with the [Bazel](https://bazel.build/).
It is designed to be running on Linux without root privileges, and no virtualization technology is required.

The build system is tested on Linux (Ubuntu/Debian).

## Prerequisites

The build system requires the following tools to be installed:

- [Bazel/Bazelisk](https://bazel.build/install/bazelisk), Bazelisk is recommended to ensure the correct version of Bazel is used.
- [Build Dependencies](https://github.com/Kong/kong/blob/master/DEVELOPER.md#prerequisites), the build system requires the same dependencies as Kong itself.
- [Cargo](https://doc.rust-lang.org/cargo/getting-started/installation.html), Rust package manager.
  - This is required to build the Rust router.

The below tools are only required for building the official Kong packages:

- [RootlessKit](https://github.com/rootless-containers/rootlesskit)
  - dependencies: `sudo apt install uidmap`
  - `sudo sh -c "echo 1 > /proc/sys/kernel/unprivileged_userns_clone"`
  - This is only required for running the build system on Linux.
- [nFPM](https://nfpm.goreleaser.com/install/), a simple deb and rpm packager.

## Building

To build the OpenResty, run the following command:

```bash
bazel build //build/openresty:openresty --action_env=DOWNLOAD_ROOT=(pwd)/work --action_env=INSTALL_ROOT=(pwd)/buildroot --verbose_failures
```

Additionally, to build the Kong Enterprise packages, run the following command:

```bash
bazel build :kong-pkg --verbose_failures
```

### Official build

`--config release` specifies the build configuration to use for release,
this indicates that the build is installed in `/usr/local/` instead of `/usr/local/kong`.

```bash
GITHUB_TOKEN=token bazel build --config release //build/openresty:openresty --verbose_failures
bazel build :kong-pkg --verbose_failures
```

Run `bazel clean` to clean the bazel build cache.

## Troubleshooting

Run `bazel build` with `--sanbox_debug --verbose_failures` to get more information about the error.

Run `rm -rf /tmp/build && rm -rf /tmp/work` to clean the build cache.

The `.log` files in `bazel-bin` contain the build logs.

## FAQ

### Caching

Bazel utilizes a cache to speed up the build process. To completely remove the entire working tree created by a Bazel instance, run:

```shell
bazel clean --expunge
```

Note there's also cache exist in `/tmp/build` and `/tmp/work` directories. The may be moved to Bazel cache
in the futre, for now, user need to manually delete those files.

```shell
rm -rf /tmp/build && rm -rf /tmp/work
```

### Cleanup

In some cases where the build fails or the build is interrupted, the build system may leave behind some temporary files. To clean up the build system, run the following command or simply rerun the build:

```shell
bazel clean
```
