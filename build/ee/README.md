** THIS DOCUMENT IS DEPRECATED, PLEASE REFER TO build/README.md FOR BUILDING BOTH EE AND CE.**

# Concepts

In addition to the standard OpenResty, the Enterprise Edition of OpenResty includes the following features:

- `--ssl-provider` option to `kong-ngx-build` for specifying the SSL provider to use. Currently only `openssl` is supported.
- `--resty-websocket` option to `kong-ngx-build` for enabling the `resty.websocket` module.
- `pre-install` and `post-install` hooks to install Enterprise Edition specific binaries and files.

Due to the nature of the Enterprise Edition, the build process is a little different from the standard OpenResty build process.
It may takes a little longer to build the Enterprise Edition of OpenResty.

It's recommended to use the Bazel to build the dependencies of the Enterprise Edition of OpenResty.

# Build

This directory contains the build system for the project.
The build system is designed to be used with the [Bazel](https://bazel.build/).
It is designed to be running on Linux without root privileges, and no virtualization technology is required.

The build system is tested on Linux (Ubuntu/Debian).

## Prerequisites

The build system requires the following tools to be installed:

- [Bazel/Bazelisk](https://bazel.build/install/bazelisk), Bazelisk is recommended to ensure the correct version of Bazel is used.
  - `sudo wget -O /usr/local/bin/bazel https://github.com/bazelbuild/bazelisk/releases/download/v1.15.0/bazelisk-linux-amd64 && sudo chmod +x /usr/local/bin/bazel`
- [Build Dependencies](https://github.com/Kong/kong/blob/master/DEVELOPER.md#prerequisites), the build system requires the same dependencies as Kong itself.
- [GitHub Personal Access Token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
  - Generate Personal access tokens (classic) with `repo` scope.
  - This is required to download the Kong Enterprise source code from GitHub.
- [Cargo](https://doc.rust-lang.org/cargo/getting-started/installation.html), Rust package manager.
  - `curl https://sh.rustup.rs -sSf | sh`
  - This is required to build the Rust router.
- EE Build Dependencies
  - dependencies: `sudo apt install libgmp-dev libtool libssl-dev`

The below tools are only required for building the official Kong Enterprise packages:

- [RootlessKit](https://github.com/rootless-containers/rootlesskit)
  - `curl -sSL https://github.com/rootless-containers/rootlesskit/releases/download/v1.1.0/rootlesskit-$(uname -m).tar.gz | sudo tar Cxzv /usr/local/bin`
  - dependencies: `sudo apt install uidmap`
  - `sudo sh -c "echo 1 > /proc/sys/kernel/unprivileged_userns_clone"`
  - This is only required for running the build system on Linux.
  ```

## Building

Currently, it only supports installing the Enterprise Edition of OpenResty to `/usr/local`.

### Official build

`--config release` specifies the build configuration to use for release,
this indicates that the build is installed in `/usr/local/` instead of `/usr/local/kong`.

```bash
git submodule update --init
GITHUB_TOKEN=token bazel build --config release //build/ee:openresty-bundle --verbose_failures
bazel build :kong --verbose_failures
```

Supported build targets:
- `:kong_deb`
- `:kong_el7`
- `:kong_el8`
- `:kong_aws2`
- `:kong_aws2022`

For example, to build the deb package:

```bash
bazel build :kong_deb
```

#### PGP Signing

PGP singing is supported for the rpm packages (`el*` and `aws*`).

```bash
bazel build //:kong_el8 --action_env=RPM_SIGNING_KEY_FILE --action_env=NFPM_RPM_PASSPHRASE
```

Run `bazel clean` to clean the bazel build cache.

## Troubleshooting

Run `bazel build` with `--sanbox_debug --verbose_failures` to get more information about the error.

Run `rm -rf /tmp/build && rm -rf /tmp/work` to clean the build cache.

The `.log` files in `bazel-bin` contain the build logs.

## FAQ

### ldconfig

https://askubuntu.com/questions/631275/how-do-i-do-this-install-you-may-need-to-run-ldconfig

### `failed to run command: sh ./configure --prefix=/usr/local/openresty/nginx \...`

```bash
git submodule update --init
```
