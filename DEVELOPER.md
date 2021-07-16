
## Development

We encourage community contributions to Kong. To make sure it is a smooth
experience (both for you and for the Kong team), please read
[CONTRIBUTING.md](CONTRIBUTING.md), [DEVELOPER.md](DEVELOPER.md),
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), and [COPYRIGHT](COPYRIGHT) before
you start.

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
- [Master Builds][kong-master-builds]: Docker images for each commit in the `master` branch.

You can find every supported distribution at the [official installation page](https://konghq.com/install/#kong-community).

#### Docker

You can use Docker / docker-compose and a mounted volume to develop Kong by
following the instructions on [Kong/kong-build-tools](https://github.com/Kong/kong-build-tools#developing-kong).

#### Kong Gojira

[Gojira](https://github.com/Kong/gojira) is a CLI that uses docker-compose
internally to make the necessary setup of containers to get all
dependencies needed to run a particular branch of Kong locally, as well
as easily switching across versions, configurations and dependencies. It
has support for running Kong in Hybrid (CP/DP) mode, testing migrations,
running a Kong cluster, among other [features](https://github.com/Kong/gojira/blob/master/doc/manual.md).

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
requires some additional third-party dependencies. We recommend installing
those by following the [source install instructions](https://docs.konghq.com/install/source/).

Instead of following the second step (Install Kong), clone this repository
and install the latest Lua sources instead of the currently released ones:

```shell
$ git clone https://github.com/Kong/kong
$ cd kong/

# you might want to switch to the development branch. See CONTRIBUTING.md
$ git checkout master

# install the Lua sources
$ luarocks make
```

#### Running for development

Check out the [development section](https://github.com/Kong/kong/blob/master/kong.conf.default#L244)
of the default configuration file for properties to tweak to ease
the development process for Kong.

Modifying the [`lua_package_path`](https://github.com/openresty/lua-nginx-module#lua_package_path)
and [`lua_package_cpath`](https://github.com/openresty/lua-nginx-module#lua_package_cpath)
directives will allow Kong to find your custom plugin's source code wherever it
might be in your system.

#### Tests

Install the development dependencies ([busted], [luacheck]) with:

```shell
$ make dev
```

Kong relies on three test suites using the [busted] testing library:

* Unit tests
* Integration tests, which require Postgres and Cassandra to be up and running
* Plugins tests, which require Postgres to be running

The first can simply be run after installing busted and running:

```
$ make test
```

However, the integration and plugins tests will spawn a Kong instance and
perform their tests against it. Because these test suites perform their tests against the Kong instance, you may need to edit the `spec/kong_tests.conf`
configuration file to make your test instance point to your Postgres/Cassandra
servers, depending on your needs.

You can run the integration tests (assuming **both** Postgres and Cassandra are
running and configured according to `spec/kong_tests.conf`) with:

```
$ make test-integration
```

And the plugins tests with:

```
$ make test-plugins
```

Finally, all suites can be run at once by simply using:

```
$ make test-all
```

Consult the [run_tests.sh](.ci/run_tests.sh) script for a more advanced example
usage of the test suites and the Makefile.

Finally, a very useful tool in Lua development (as with many other dynamic
languages) is performing static linting of your code. You can use [luacheck]
\(installed with `make dev`\) for this:

```
$ make lint
```

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


## Virtual Machine

Final deployments are typically on a Linux machine or container, so even if all components are multiplatform, it's easier to use it for development too.  If you use MacOS or Windows machines, setting a virtual machine is easy enough now.  Most of us use the freely available VirtualBox without any trouble.

If you use Linux for your desktop, you can skip this section.

There are no "hard" requirements on any Linux distro, but RHEL and CentOS can be more of a challenge to get recent versions of many packages; Fedora, Debian or Ubuntu are easier for this.

To avoid long compilation times, give the VM plenty of RAM (8GB recommended) and all the CPU cores you can.

### Virtual Box setup

You will need to setup port forwarding on VirtualBox to be able to ssh into the box which can be done as follows:

1. Select the virtual machine you want to use and click "Settings"
1. Click "Network" tab
1. Click "Advanced" dropdown
1. Click "Port Forwarding"
1. Add a new rule in the popup. The only thing you will need is "Host Port" to be 22222 and "Guest Port" to be 22. Everything else can be left default (see screenshot below)
1. Click "Ok"

Now you should be able to `ssh <your_name>@127.1 -p 22222` to get SSH prompt. However, this requires us to type a long command and password every time we sign in. It is recommended you setup a public key and SSH alias to make this process simpler:

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

Now try `ssh dev` on your host, you should be able to get into the guest directly

## Linux Environment

Once you have a Linux development environment (either virtual or bare metal), the build is done in four separate steps:

1. Prerequisite packages.  Mostly compilers, tools and libraries needed to compile everything else.
1. OpenResty system, including Nginx, LuaJIT, PCRE, etc.
1. Databases. Kong uses Postgres, Cassandra and Redis.  We have a handy setup with docker-compose to keep each on its container.
1. Kong itself.


### Prerequisites

These are the needed tools and libraries that aren't installed out of the box on Ubuntu and Fedora, respectively.  Just run one of these, either as root or `sudo`.

Ubuntu:

```shell
    apt-get update

    apt-get install \
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
        zlib1g-dev
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
        zlib-devel
```

### OpenResty

We have a build script that makes it easy to pull and compile specific versions of the needed components of the OpenResty system.  Currently these include OpenResty 1.15.8.3, OpenSSl 1.1.1g, LuaRocks 3.3.1 and PCRE 8.44;  the exact versions can also be found on the [`.requirements`](https://github.com/Kong/kong/blob/master/.requirements) file of the main Kong repository.

These commands don't have to be performed as root, since all compilation is done within a subdirectory, and installs everything in the target specified by the `-p` argument (here the `build` directory).

```
    git clone https://github.com/kong/kong-build-tools

    cd kong-build-tools/openresty-build-tools

    ./kong-ngx-build -p build \
        --openresty 1.15.8.3 \
        --openssl 1.1.1g \
        --luarocks 3.3.1 \
        --pcre 8.44
```

After this task, we'd like to have the next steps use the built packages and for LuaRocks to install new packages inside this `build` directory.  For that, it's important to set the `$PATH` variable accordingly:

```
    export PATH=$HOME/path/to/kong-build-tools/openresty-build-tools/build/openresty/bin:$HOME/path/to/kong-build-tools/openresty-build-tools/build/openresty/nginx/sbin:$HOME/path/to/kong-build-tools/openresty-build-tools/build/luarocks/bin:$PATH
    export OPENSSL_DIR=$HOME/path/to/kong-build-tools/openresty-build-tools/build/openssl

    eval `luarocks path`
```

The `$OPENSSL_DIR` variable is needed when compiling Kong, to make sure it uses the correct version of OpenSSL.

You can add these lines to your `.profile` or `.bashrc` file.  Otherwise you could find yourself wondering where is everything!.


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
