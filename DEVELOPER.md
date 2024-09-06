
## Development

We encourage community contributions to Kong. To make sure it is a smooth
experience (both for you and for the Kong team), please read
[CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md),
and [COPYRIGHT](COPYRIGHT) before you start.

If you are planning on developing on Kong, you'll need a development
installation. The `master` branch holds the latest unreleased source code.

You can read more about writing your own plugins in the [Plugin Development
Guide](https://docs.konghq.com/gateway/latest/plugin-development/), or browse an
online version of Kong's source code documentation in the [Plugin Development
Kit (PDK) Reference](https://docs.konghq.com/latest/pdk/).

For a quick start with custom plugin development, check out [Pongo](https://github.com/Kong/kong-pongo)
and the [plugin template](https://github.com/Kong/kong-plugin) explained in detail below.


## Distributions

Kong comes in many shapes. While this repository contains its core's source
code, other repos are also under active development:

- [Kubernetes Ingress Controller for Kong](https://github.com/Kong/kubernetes-ingress-controller):
  Use Kong for Kubernetes Ingress.
- [Binary packages](https://docs.konghq.com/gateway/latest/install/)
- [Kong Docker](https://github.com/Kong/docker-kong): A Dockerfile for
  running Kong in Docker.
- [Kong Packages](https://github.com/Kong/kong/releases): Pre-built packages
  for Debian, Red Hat, and OS X distributions (shipped with each release).
- [Kong Homebrew](https://github.com/Kong/homebrew-kong): Homebrew Formula
  for Kong.
- [Kong AWS AMI](https://aws.amazon.com/marketplace/pp/B06WP4TNKL): Kong AMI on
  the AWS Marketplace.
- [Kong on Microsoft Azure](https://github.com/Kong/kong-dist-azure): Run Kong
  using Azure Resource Manager.
- [Kong on Heroku](https://github.com/heroku/heroku-kong): Deploy Kong on
  Heroku in one click.
- [Kong on IBM Cloud](https://github.com/andrew40404/installing-kong-IBM-cloud) - How to deploy Kong on IBM Cloud
- [Kong and Instaclustr](https://www.instaclustr.com/solutions/managed-cassandra-for-kong/): Let
  Instaclustr manage your Cassandra cluster.
- [Master Builds](https://hub.docker.com/r/kong/kong): Docker images for each commit in the `master` branch.

You can find every supported distribution on the [official installation page](https://konghq.com/install/#kong-community).

#### Kong Pongo

[Pongo](https://github.com/Kong/kong-pongo) is a CLI tool that are
specific for plugin development. It is docker-compose based and will
create local test environments including all dependencies. Core features
are running tests, integrated linter, config initialization, CI support,
and custom dependencies.

#### Kong Plugin Template

The [plugin template](https://github.com/Kong/kong-plugin) provides a basic
plugin and is considered a best-practices plugin repository. When writing
custom plugins, we strongly suggest you start by using this repository as a
starting point. It contains the proper file structures, configuration files,
and CI setup to get up and running quickly. This repository seamlessly
integrates with [Pongo](https://github.com/Kong/kong-pongo).

## Build and Install from source

This is the hard way to build a development environment, and also a good start
for beginners to understand how everything fits together.

Kong is mostly an OpenResty application made of Lua source files, but also
requires some additional third-party dependencies, some of which are compiled
with tweaked options, and kong runs on a modified version of OpenResty with
patches.

To install from the source, first, we clone the repository:

```shell
git clone https://github.com/Kong/kong

cd kong
# You might want to switch to the development branch. See CONTRIBUTING.md
git checkout master

```

Then we will install the dependencies:

Ubuntu/Debian:

```shell
sudo apt update \
&& sudo apt install -y \
    automake \
    build-essential \
    curl \
    file \
    git \
    libyaml-dev \
    libprotobuf-dev \
    m4 \
    perl \
    pkg-config \
    procps \
    unzip \
    valgrind \
    zlib1g-dev

```

Fedora/RHEL:

```shell
dnf install \
    automake \
    gcc \
    gcc-c++ \
    git \
    libyaml-devel \
    make \
    patch \
    perl \
    perl-IPC-Cmd \
    protobuf-devel \
    unzip \
    valgrind \
    valgrind-devel \
    zlib-devel
```

macOS

```shell
# Install Xcode from App Store (Command Line Tools is not supported)

# Install HomeBrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# Build dependencies
brew install libyaml
```

Now, you have to authenticate with GitHub to download some essential repos
using either one of the following ways:
* Download [`gh cli`](https://cli.github.com/) and run `gh auth login` once.
* Use a [Personal Access Token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token). This token does not need to have any other permission than `Public Repositories (read-only)`, and set it as `GITHUB_TOKEN` environment variable.
* Use [git credential helper](https://git-scm.com/docs/gitcredentials).

Then you have to make the Rust build system also authenticate with GitHub,
there is nothing you need to do if you were authenticated using `gh` or `git credential helper`,
otherwise, you can set the[`CARGO_NET_GIT_FETCH_WITH_CLI`](https://doc.rust-lang.org/cargo/reference/config.html)
environment variable to `true`.

```shell
export CARGO_NET_GIT_FETCH_WITH_CLI=true
```

An alternative is to edit the `~/.cargo/config` file and add the following lines:

```toml
[net]
git-fetch-with-cli = true
```

You also have to make sure the `git` CLI is using the proper protocol to fetch the dependencies
if you are authenticated with
[Personal Access Token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token).

```shell
# If you are using the HTTPS protocol to clone the repository
# YOU ONLY NEED TO DO THIS ONLY ONCE FOR THIS DIRECTORY
git config --local url."https://${GITHUB_TOKEN}@github.com/".insteadOf 'git@github.com:'
git config --local url."https://${GITHUB_TOKEN}@github.com".insteadOf 'https://github.com'


# If you are using the SSH protocol to clone the repository
# YOU ONLY NEED TO DO THIS ONLY ONCE FOR THIS DIRECTORY
git config --local url.'git@github.com:'.insteadOf 'https://github.com'
git config --local url.'ssh://git@github.com/'.insteadOf 'https://github.com/'
```

Finally, we start the build process:

```
# Build the virtual environment for developing Kong
make build-venv
```

[The build guide](https://github.com/Kong/kong/blob/master/build/README.md) contains a troubleshooting section if
you face any problems. It also describes the build process in detail, if you want to development on the build
system itself.

### Start Kong

Now you can start Kong:

```shell
# Activate the venv by adding some environment variables and populate helper functions
# into your current shell session, following functions are exported:
# `start_services`, `stop_services` and `deactivate`
# For Zsh/Bash:
. bazel-bin/build/kong-dev-venv.sh
# For Fish Shell:
. bazel-bin/build/kong-dev-venv.fish

# Use the pre-defined docker-compose file to bring up databases etc
start_services

# Start Kong!
kong start

# Stop Kong
kong stop

# Cleanup
deactivate
```

### Install Development Dependencies

#### Running for development

By default, the development environment adds current directory to Lua files search path.

Modifying the [`lua_package_path`](https://github.com/openresty/lua-nginx-module#lua_package_path)
and [`lua_package_cpath`](https://github.com/openresty/lua-nginx-module#lua_package_cpath)
directives will allow Kong to find your custom plugin's source code wherever it
might be in your system.

#### Tests

Install the development dependencies ([busted](https://lunarmodules.github.io/busted/),
[luacheck](https://github.com/mpeterv/luacheck)) with:

```shell
make dev
```

If Rust/Cargo doesn't work, try setting `export KONG_TEST_USER_CARGO_DISABLED=1` first.

Kong relies on three test suites using the [busted](https://lunarmodules.github.io/busted/) testing library:

* Unit tests
* Integration tests, which require Postgres and Cassandra to be up and running
* Plugins tests, which require Postgres to be running

The first can simply be run after installing busted and running:

```
make test
```

However, the integration and plugins tests will spawn a Kong instance and
perform their tests against it. Because these test suites perform their tests
against the Kong instance, you may need to edit the `spec/kong_tests.conf`
configuration file to make your test instance point to your Postgres/Cassandra
servers, depending on your needs.

You can run the integration tests (assuming **both** Postgres and Cassandra are
running and configured according to `spec/kong_tests.conf`) with:

```
make test-integration
```

And the plugins tests with:

```
make test-plugins
```

Finally, all suites can be run at once by simply using:

```
make test-all
```

Consult the [run_tests.sh](.ci/run_tests.sh) script for more advanced example
usage of the test suites and the Makefile.

Finally, a very useful tool in Lua development (as with many other dynamic
languages) is performing static linting of your code. You can use
[luacheck](https://github.com/mpeterv/luacheck)
\(installed with `make dev`\) for this:

```
make lint
```

#### Upgrade tests

Kong Gateway supports no-downtime upgrades through its database schema
migration mechanism (see [UPGRADE.md](./UPGRADE.md)).  Each schema
migration needs to be written in a way that allows the previous and
the current version of Kong Gateway run against the same database
during upgrades.  Once all nodes have been upgraded to the current
version of Kong Gateway, additional changes to the database can be
made that are incompatible with the previous version.  To support
that, each migration is split into two parts, an `up` part that can
only make backwards-compatible changes, and a `teardown` part that
runs after all nodes have been upgraded to the current version.

Each migration that is contained in Kong Gateway needs to be
accompanied with a test that verifies the correct operation of both
the previous and the current version during an upgrade.  These tests
are located in the [spec/05-migration/](spec/05-migration/) directory
and must be named after the migration they test such that the
migration `kong/**/*.lua` has a test in
`spec/05-migration/**/*_spec.lua`.  The presence of a test is enforced
by the [upgrade testing](scripts/upgrade-tests/test-upgrade-path.sh) shell script
which is [automatically run](.github/workflows/upgrade-tests.yml)
through a GitHub Action.

The [upgrade testing](scripts/upgrade-tests/test-upgrade-path.sh) shell script works
as follows:

 * A new Kong Gateway installation is brought up using
   [Gojira](https://github.com/Kong/gojira), consisting of one node
   containing the previous version of Kong Gateway ("OLD"), one node
   containing the current version of Kong Gateway ("NEW") and a shared
   database server (PostgreSQL or Cassandra).
 * NEW: The database is initialized using `kong migrations bootstrap`.
 * OLD: The `setup` phase of all applicable migration tests is run.
 * NEW: `kong migrations up` is run to run the `up` part of all
   applicable migrations.
 * OLD: The `old_after_up` phase of all applicable migration tests is
   run.
 * NEW: The `new_after_up` phase of all applicable migration tests is
   run.
 * NEW: `kong migrations finish` is run to invoke the `teardown` part
   of all applicable migrations.
 * NEW: The `new_after_finish` phase of all applicable migration tests
   is run.

Upgrade tests are run using [busted](https://github.com/lunarmodules/busted).
To support the specific testing
method of upgrade testing, a number of helper functions are defined in
the [spec/upgrade_helpers.lua](spec/upgrade_helpers.lua) module.
Migration tests use functions from this module to define test cases
and associate them with phases of the upgrade testing process.
Consequently, they are named `setup`, `old_after_up`, `new_after_up`
and `new_after_finish`.  Additionally, the function `all_phases` can be
used to run a certain test in the three phases `old_after_up`,
`new_after_up` and `new_after_finish`.  These functions replace the
use of busted's `it` function and accept a descriptive string and a
function as argument.

It is important to note that upgrade tests need to run on both the old
and the new version of Kong.  Thus, they can only use features that
are available in both versions (i.e. from helpers.lua).  The module
[spec/upgrade_helpers.lua](spec/upgrade_helpers.lua) is copied from
the new version into the container of the old version and it can be
used to make new library functionality available to migration tests.

#### Makefile

When developing, you can use the `Makefile` for doing the following operations:

| Name               | Description                                            |
| ------------------:| -------------------------------------------------------|
| `install`          | Install the Kong luarock globally                      |
| `dev`              | Install development dependencies                       |
| `lint`             | Lint Lua files in `kong/` and `spec/`                  |
| `test`             | Run the unit tests suite                               |
| `test-integration` | Run the integration tests suite                        |
| `test-plugins`     | Run the plugins test suite                             |
| `test-all`         | Run all unit + integration + plugins tests at once     |

### Setup Hybrid Mode Development Environment

You can follow the steps given below to setup a hybrid mode environment.

1. Activate the venv

   ```bash
   # . bazel-bin/build/kong-dev-venv.sh
   ```

2. Following [Deploy Kong Gateway in Hybrid Mode: Generate certificate/key pair](https://docs.konghq.com/gateway/latest/production/deployment-topologies/hybrid-mode/setup/#generate-a-certificatekey-pair) to generate a certificate/key pair.

3. Create CP and DP configuration files, such as `kong-cp.conf` and `kong-dp.conf`.

4. Following [Deploy Kong Gateway in Hybrid Mode: CP Configuration](https://docs.konghq.com/gateway/latest/production/deployment-topologies/hybrid-mode/setup/#set-up-the-control-plane) to configure CP using `kong.conf`.

5. Following [Deploy Kong Gateway in Hybrid Mode: DP Configuration](https://docs.konghq.com/gateway/latest/production/deployment-topologies/hybrid-mode/setup/#install-and-start-data-planes) to configure DP using `kong.conf`.

6. Unset environment variable `KONG_PREFIX` to ensure configuration directive `prefix` in configuration file is enabled.

7. Modify or add the directive `prefix` to `kong-cp.conf` and `kong-dp.conf`
to be `prefix=servroot-cp` and `prefix=servroot-dp`,
or other names you want, but make sure they are different.

8. Use the pre-defined docker-compose file to bring up databases, etc.

   ```bash
   # start_services
   ```

9. If it is the first time to start Kong, you have to execute the following command to CP node.

   ```bash
   # kong migrations bootstrap -c kong-cp.conf
   ```

10. Start CP and DP. `kong start -c kong-cp.conf` and `kong start -c kong-dp.conf`.

11. To stop CP and DP, you can execute `kong stop -p servroot-cp` and
`kong stop -p servroot-dp` in this example.
Names `servroot-cp` and `servroot-dp` are set in configuration file in step 7.



## Dev on Linux (Host/VM)

If you have a Linux development environment (either virtual or bare metal), the build is done in four separate steps:

1. Development dependencies and runtime libraries, including:
   1. Prerequisite packages.  Mostly compilers, tools, and libraries required to compile everything else.
   2. OpenResty system, including Nginx, LuaJIT, PCRE, etc.
2. Databases. Kong uses Postgres, Cassandra, and Redis.  We have a handy setup with docker-compose to keep each on its container.
3. Kong itself.

### Virtual Machine (Optional)

Final deployments are typically on a Linux machine or container, so even if all components are multiplatform,
it's easier to use it for development too. If you use macOS or Windows machines, setting up a virtual machine
is easy enough now. Most of us use the freely available VirtualBox without any trouble.

If you use Linux for your desktop, you can skip this section.

There are no "hard" requirements on any Linux distro, but RHEL and CentOS can be more of a challenge
to get recent versions of many packages; Fedora, Debian, or Ubuntu are easier for this.

To avoid long compilation times, give the VM plenty of RAM (8GB recommended) and all the CPU cores you can.

#### Virtual Box setup

You will need to setup port forwarding on VirtualBox to be able to ssh into the box which can be done as follows:

1. Select the virtual machine you want to use and click "Settings"
1. Click the "Network" tab
1. Click the "Advanced" dropdown
1. Click "Port Forwarding"
1. Add a new rule in the popup. The only thing you will need is "Host Port" to be 22222 and "Guest Port" to be 22. Everything else can be left default (see screenshot below)
1. Click "Ok"

Now you should be able to `ssh <your_name>@127.1 -p 22222` to get SSH prompt. However, this requires us to type a long command and password every time we sign in. It is recommended you set up a public key and SSH alias to make this process simpler:

1. On your host machine, generate a keypair for SSH into the guest: `ssh-keygen -t ed25519`.
Just keep hitting Enter until the key is generated. You do not need a password for this key file since it is only used for SSH into your guest
1. Type `cat .ssh/id_ed25519.pub` and copy the public key
1. SSH into the guest using the command above
1. Create the ssh config directory (if it doesn't exist) `$ mkdir -p .ssh`
1. Edit the authorized keys list: `vim .ssh/authorized_keys`
1. Paste in the content of .ssh/id_ed25519.pub
1. Adjust the required privileges: `chmod 700 .ssh/`  and `chmod 400 .ssh/authorized_keys`
1. Logout of guest and make sure you are not promoted password when SSH again
1. Edit the .ssh/config file on your host and put in the following content:

```
    Host dev
        HostName 127.1
        Port 22222
        User <your_user_name>
```

Now try `ssh dev` on your host, you should be able to get into the guest directly.

## Dev on VSCode Container / GitHub Codespaces

The `devcontainer.json` file in Kong's project tells VS Code
how to access (or create) a development container with a well-defined tool and runtime stack.

- See [How to create a GitHub codespace](https://docs.github.com/en/codespaces/developing-in-codespaces/creating-a-codespace#creating-a-codespace).
- See [How to create a VSCode development container](https://code.visualstudio.com/docs/remote/containers#_quick-start-try-a-development-container).

## Debugging Kong Gateway with EmmyLua and IntelliJ IDEA/VSCode

[EmmyLua](https://emmylua.github.io/) is a plugin for IntelliJ IDEA and VSCode that provides Lua language
support.  It comes with debugger support that makes it possible to set breakpoints in Lua code
and inspect variables.  Kong Gateway can be debugged using EmmyLua by following these steps:

### Install the IDE

#### IntelliJ IDEA

Download and install IntelliJ IDEA from [here](https://www.jetbrains.com/idea/download/).  Note
that IntelliJ is a commercial product and requires a paid license after the trial period.

#### VSCode

Download and install MS Visual Studio Code from [here](https://code.visualstudio.com/download).

### Install EmmyLua

#### IntelliJ IDEA

Go to the `Settings`->`Plugins`->`Marketplace` and search for `EmmyLua`.
Install the plugin.

#### VSCode

Go to the `Settings`->`Extensions` and search for `EmmyLua`.
Install the plugin (publisher is `Tangzx`).

### Download and install the EmmyLua debugging server

The [EmmyLuaDebugger](https://github.com/EmmyLua/EmmyLuaDebugger) is a standalone C++ program
that runs on the same machine as Kong Gateway and that mediates between the IDE's
debugger and the Lua code running in Kong Gateway.  It can be downloaded from
[GitHub](https://github.com/EmmyLua/EmmyLuaDebugger/releases).  The release
ZIP file contains a single shared library named emmy_core.so (Linux) or emmy_core.dylib (macOS).
Place this file in a directory that is convenient for you and remember the path.

Depending on your Linux version, you may need to compile
[EmmyLuaDebugger](https://github.com/EmmyLua/EmmyLuaDebugger) on your
own system as the release binaries published on GitHub assume a pretty
recent version of GLIBC to be present.

### Start Kong Gateway with the EmmyLua debugger

To enable the EmmyLua debugger, the `KONG_EMMY_DEBUGGER` environment variable must be set to
the absolute path of the debugger shared library file when Kong Gateway is started.  It is
also advisable to start Kong Gateway with only one worker process, as debugging multiple worker
processes requires special care.  For example:

```shell
KONG_EMMY_DEBUGGER=/path/to/emmy_core.so KONG_NGINX_WORKER_PROCESSES=1 kong start
```

### Create debugger configuration

#### IntelliJ IDEA

Go to `Run`->`Edit Configurations` and click the `+` button to add a new
configuration.  Select `Emmy Debugger(NEW)` as the configuration type.  Enter a descriptive
name for the configuration, e.g. "Kong Gateway Debug".  Click `OK` to save the configuration.

#### VSCode

Go to `Run`->`Add Configuration` and choose `EmmyLua New Debugger`. Enter a descriptive name
for the configuration, e.g. "Kong Gateway Debug". Save `launch.json`.

### Start the EmmyLua debugger

To connect the EmmyLua debugger to Kong Gateway, click the `Run`->`Debug` menu item in IntelliJ
(`Run`->`Start Debugging` in VSCode) and select the configuration that you've just created.  You
will notice that the restart and stop buttons on the top of your IDE will change to solid green
and red colors.  You can now set breakpoints in your Lua code and start debugging.  Try setting
a breakpoint in the global `access` function that is defined `runloop/handler.lua` and send
a proxy request to the Gateway.  The debugger should stop at the breakpoint and you can
inspect the variables in the request context.

### Debugging `busted` tests

To debug `busted` tests, you can set the `BUSTED_EMMY_DEBUGGER` environment variable to the path
to the EmmyLua debugger shared library.  When debugging is enabled, `busted` will always wait for
the IDE to connect during startup.

### Debugging environment variables

The following environment variables can be set to control the behavior of the EmmyLua debugger
integration:

- `KONG_EMMY_DEBUGGER`: The path to the EmmyLua debugger shared library.
- `KONG_EMMY_DEBUGGER_HOST`: The IP address that the EmmyLua debugger will listen on.  The default
  is `localhost`.
- `KONG_EMMY_DEBUGGER_PORT`: The port that the EmmyLua debugger will listen on.  The default is
  `9966`.
- `KONG_EMMY_DEBUGGER_WAIT`: If set, Kong Gateway will wait for the debugger to connect
  before starting continuing to start.
- `KONG_EMMY_DEBUGGER_SOURCE_PATH`: The path to the source code that the EmmyLua debugger will
  use to resolve source code locations.  The default is the current working directory.
- `KONG_EMMY_DEBUGGER_MULTI_WORKER`: If set, a debugger will be started for each worker process, using
  incrementing port numbers starting at `KONG_EMMY_DEBUGGER_PORT`.  The default is to start
  only one debugger for worker zero.

To control debugger behavior while running `busted` tests, a similar set of environment variables
prefixed with `BUSTED_` instead of `KONG_` can be used.

## What's next

- Refer to the [Kong Gateway Docs](https://docs.konghq.com/gateway/) for more information.
- Learn about [lua-nginx-module](https://github.com/openresty/lua-nginx-module).
- Learn about [lua-resty-core](https://github.com/openresty/lua-resty-core).
- Learn about the fork [luajit2](https://github.com/openresty/luajit2) of OpenResty.
- For profiling, see [stapxx](https://github.com/openresty/stapxx), the SystemTap framework for OpenResty.
