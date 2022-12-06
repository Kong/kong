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
bazel build //build/openresty:openresty --verbose_failures
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

### ldconfig

https://askubuntu.com/questions/631275/how-do-i-do-this-install-you-may-need-to-run-ldconfig
