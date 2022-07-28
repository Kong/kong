
## Development

We encourage community contributions to Kong. To make sure it is a smooth
experience (both for you and for the Kong team), please read
[CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md),
and [COPYRIGHT](COPYRIGHT) before you start.

If you are planning on developing on Kong, you'll need a development
installation. The `master` branch holds the latest unreleased source code.

You can read more about writing your own plugins in the [Plugin Development
Guide](https://docs.konghq.com/latest/plugin-development/), or browse an
online version of Kong's source code documentation in the [Plugin Development
Kit (PDK) Reference](https://docs.konghq.com/latest/pdk/).

For a quick start with custom plugin development, check out [Pongo](https://github.com/Kong/kong-pongo)
and the [plugin template](https://github.com/Kong/kong-plugin) explained in detail below.


## Distributions

Kong comes in many shapes. While this repository contains its core's source
code, other repos are also under active development:

- [Kubernetes Ingress Controller for Kong](https://github.com/Kong/kubernetes-ingress-controller):
  Use Kong for Kubernetes Ingress.
- [Kong Docker](https://github.com/Kong/docker-kong): A Dockerfile for
  running Kong in Docker.
- [Kong Packages](https://github.com/Kong/kong/releases): Pre-built packages
  for Debian, Red Hat, and OS X distributions (shipped with each release).
- [Kong Gojira](https://github.com/Kong/gojira): A tool for
  testing/developing multiple versions of Kong using containers.
- [Kong Vagrant](https://github.com/Kong/kong-vagrant): A Vagrantfile for
  provisioning a development-ready environment for Kong.
- [Kong Homebrew](https://github.com/Kong/homebrew-kong): Homebrew Formula
  for Kong.
- [Kong CloudFormation](https://github.com/Kong/kong-dist-cloudformation):
  Kong in a 1-click deployment for AWS EC2.
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

#### Docker

You can use Docker / docker-compose and a mounted volume to develop Kong by
following the instructions on [Kong/kong-build-tools](https://github.com/Kong/kong-build-tools#developing-kong).

#### Kong Gojira

[Gojira](https://github.com/Kong/gojira) is a CLI that uses docker-compose
internally to make the necessary setup of containers to get all
dependencies needed to run a particular branch of Kong locally, as well
as easily switching across versions, configurations and dependencies. It
has support for running Kong in Hybrid (CP/DP) mode, testing migrations,
running a Kong cluster, among other [features](https://github.com/Kong/gojira/blob/master/docs/manual.md).

#### Kong Pongo

[Pongo](https://github.com/Kong/kong-pongo) is another CLI like Gojira,
but specific for plugin development. It is docker-compose based and will
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

#### Vagrant

You can use a Vagrant box running Kong and Postgres that you can find at
[Kong/kong-vagrant](https://github.com/Kong/kong-vagrant).

#### Source Install

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

Before continuing you should go through [this section](#dependencies-build-from-source) to set up dependencies.

Then you can install the Lua source:

```shell
# go back to where the kong source locates after dependencies are set up
cd ../../kong

sudo luarocks make
```

#### Running for development

Modifying the [`lua_package_path`](https://github.com/openresty/lua-nginx-module#lua_package_path)
and [`lua_package_cpath`](https://github.com/openresty/lua-nginx-module#lua_package_cpath)
directives will allow Kong to find your custom plugin's source code wherever it
might be in your system.

#### Tests

Install the development dependencies ([busted], [luacheck]) with:

```shell
make dev
```

Kong relies on three test suites using the [busted] testing library:

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
languages) is performing static linting of your code. You can use [luacheck]
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
by the [upgrade testing](scripts/test-upgrade-path.sh) shell script
which is [automatically run](.github/workflows/upgrade-tests.yml)
through a GitHub Action.

The [upgrade testing](scripts/test-upgrade-path.sh) shell script works
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

Upgrade tests are run using [busted].  To support the specific testing
method of upgrade testing, a number of helper functions are defined in
the [spec/upgrade_helpers.lua](spec/upgrade_helpers.lua) module.
Migration tests use functions from this module to define test cases
and associate them with phases of the upgrade testing process.
Consequently, they are named `setup`, `old_after_up`, `new_after_up`
and `new_after_finish`.  Additonally, the function `all_phases` can be
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

These are the steps we follow at Kong to set up a development environment.

## Dev on Docker

[Gojira](https://github.com/Kong/gojira) is a multi-purpose tool to ease the
development and testing of Kong by using Docker containers.  It's built on
the top of Docker and Docker Compose, and separates multiple Kong development
environments into different Docker Compose stacks.  It also auto-manages the
network configuration between Kong and PostgreSQL (if required) by configuring
the containers' environment variables.

It's fully compatible with all platforms (even Apple Silicon).
You can set up your development environment with Gojira in a couple of seconds
(depending on your network speed). 

See below links to install the dependencies: 

- [Install Docker or Docker Desktop](https://docs.docker.com/get-docker/)
- [Install Docker Compose](https://docs.docker.com/compose/install/)

Install Gojira (see [full instructions](https://github.com/Kong/gojira#installation)):

```bash
git clone git@github.com:Kong/gojira.git
mkdir -p ~/.local/bin
ln -s $(realpath gojira/gojira.sh) ~/.local/bin/gojira
```

Add `export PATH=$PATH:~/.local/bin` to your `.bashrc` or `.zshrc` file.

Clone the Kong project to your development folder.

```bash
git clone git@github.com:Kong/kong.git
cd kong
```

Within the `kong` folder run the following Gojira commands to start a development
version of the Kong Gateway using PostgreSQL:

```bash
gojira up -pp 8000:8000 -pp 8001:8001
gojira run make dev
gojira run kong migrations bootstrap
gojira run kong start
```

Verify the Admin API is now available by navigating to `http://localhost:8001` on your host machine browser.

Tips: 

- Attach to shell by running `gojira shell` within `kong` folder.
- Learn about [usage patterns](https://github.com/Kong/gojira/blob/master/docs/manual.md#usage-patterns) of Gojira.

## Dev on Linux (Host/VM)

If you have a Linux development environment (either virtual or bare metal), the build is done in four separate steps:

1. Development dependencies and runtime libraries, including:
   1. Prerequisite packages.  Mostly compilers, tools, and libraries required to compile everything else.
   2. OpenResty system, including Nginx, LuaJIT, PCRE, etc.
2. Databases. Kong uses Postgres, Cassandra, and Redis.  We have a handy setup with docker-compose to keep each on its container.
3. Kong itself.

### Virtual Machine (Optional)

Final deployments are typically on a Linux machine or container,so even if all components are multiplatform,
it's easier to use it for development too.  If you use macOS or Windows machines, setting up a virtual machine
is easy enough now.  Most of us use the freely available VirtualBox without any trouble.

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

### Dependencies (Build from source)

This is the hard way to build a development environment, and also a good start for beginners to understand how everything fits together.

#### Prerequisites

These are the needed tools and libraries that aren't installed out of the box on Ubuntu and Fedora, respectively.  Just run one of these, either as root or `sudo`.

Ubuntu/Debian:

```shell
sudo apt update \
&& sudo apt install -y \
    automake \
    build-essential \
    curl \
    docker \
    docker-compose \
    git \
    libpcre3 \
    libyaml-dev \
    m4 \
    openssl \
    perl \
    procps \
    unzip \
    zlib1g-dev \
    valgrind
```

Fedora:

```shell
dnf install \
    automake \
    docker \
    docker-compose \
    gcc \
    gcc-c++ \
    git \
    libyaml-devel \
    make \
    patch \
    pcre-devel \
    unzip \
    zlib-devel \
    valgrind
```

#### OpenResty

We have a build script from [Kong/kong-ngx-build](https://github.com/Kong/kong-build-tools/tree/master/openresty-build-tools) that makes it easy to pull and compile specific versions of the needed components of the OpenResty system.

To run the script we need to find out what versions of them the current build of Kong requires, and use that as arguments. <span class="x x-first x-last">Their </span>exact versions can be found on the [`.requirements`](https://github.com/Kong/kong/blob/master/.requirements) file.

You can manually fill in the versions, or follow the steps below.

```shell
# if you are not in the directory 
# cd kong

export RESTY_VERSION=$(grep -oP 'RESTY_VERSION=\K.*' .requirements)
export RESTY_OPENSSL_VERSION=$(grep -oP 'RESTY_OPENSSL_VERSION=\K.*' .requirements)
export RESTY_LUAROCKS_VERSION=$(grep -oP 'RESTY_LUAROCKS_VERSION=\K.*' .requirements)
export RESTY_PCRE_VERSION=$(grep -oP 'RESTY_PCRE_VERSION=\K.*' .requirements)
```

These commands don't have to be performed as root, since all compilation is done within a subdirectory, and installs everything in the target specified by the `-p` argument (here the `build` directory).

```shell
# Somewhere you're able or prefer to build
export BUILDROOT=$(realpath ~/kong-dep)
mkdir ${BUILDROOT} -p

# clone the repository
cd ..
git clone https://github.com/kong/kong-build-tools

cd kong-build-tools/openresty-build-tools

# You might want to add also --debug
./kong-ngx-build -p ${BUILDROOT} \
  --openresty ${RESTY_VERSION} \
  --openssl ${RESTY_OPENSSL_VERSION} \
  --luarocks ${RESTY_LUAROCKS_VERSION} \
  --pcre ${RESTY_PCRE_VERSION}
```

After this task, we'd like to have the next steps use the built packages and for LuaRocks to install new packages inside this `build` directory.  For that, it's important to set the `$PATH` variable accordingly:

```shell
# Add those paths for later use
export OPENSSL_DIR=${BUILDROOT}/openssl
export CRYPTO_DIR=${BUILDROOT}/openssl
export PATH=${BUILDROOT}/luarocks/bin:${BUILDROOT}/openresty/bin:${PATH}
eval $(luarocks path)
```

The `$OPENSSL_DIR` variable is needed when compiling Kong, to make sure it uses the correct version of OpenSSL.

You can add these lines to your `.profile` or `.bashrc` file.  Otherwise, you could find yourself wondering where is everything!.

```shell
# If you want to set it permanently
echo export OPENSSL_DIR=${BUILDROOT}/openssl >> ~/.profile
echo export PATH=${BUILDROOT}/luarocks/bin:${BUILDROOT}/openresty/bin:\${PATH} >> ~/.profile
echo eval "\$(luarocks path)" >> ~/.profile
```
### Databases

The easiest way to handle these as a single group is via docker-compose.  It's also recommended to set your user as a [docker manager](https://docs.docker.com/install/linux/linux-postinstall/#manage-docker-as-a-non-root-user) to simplify the next steps.

Make sure the docker daemon is enabled and running: `sudo systemctl enable docker` and `sudo systemctl start docker`. Verify that `docker ps` shows no errors.

On a Fedora VM, you might have to disable SELinux:

```
sudo vim /etc/selinux/config        # change the line to SELINUX=disabled
sudo setenforce 0
```

Now pull the compose script from the repository and fire it up:

```
git clone https://github.com/thibaultcha/kong-tests-compose.git
cd kong-tests-compose
docker-compose up
```

Verify the three new containers are up and running with `docker ps` on a separate terminal.


### Install Kong

```
git clone https://github.com/Kong/kong.git
cd kong
git checkout master
make dev
```

Now run unit tests with `make test` and integration test with `make test-integration`.

Hack on!

## Dev on VSCode Container / GitHub Codespaces

The `devcontainer.json` file in Kong's project tells VS Code 
how to access (or create) a development container with a well-defined tool and runtime stack.

- See [How to create a GitHub codespace](https://docs.github.com/en/codespaces/developing-in-codespaces/creating-a-codespace#creating-a-codespace).
- See [How to create a VSCode development container](https://code.visualstudio.com/docs/remote/containers#_quick-start-try-a-development-container).

## What's next

- Refer to the [Kong Gateway Docs](https://docs.konghq.com/gateway/) for more information.
- Learn about [lua-nginx-module](https://github.com/openresty/lua-nginx-module).
- Learn about [lua-resty-core](https://github.com/openresty/lua-resty-core).
- Learn about the fork [luajit2](https://github.com/openresty/luajit2) of OpenResty.
- For profiling, see [stapxx](https://github.com/openresty/stapxx), the SystemTap framework for OpenResty.
