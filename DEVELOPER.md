
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

Now you should be able to ssh <your_name>@127.1 -p 22222 to get SSH prompt. However, this requires us to type a long command and password every time we sign in. It is recommended you setup a public key and SSH alias to make this process simpler:

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

Now try ssh dev on your host, you should be able to get into the guest directly

## Linux Environment

Once you have a Linux development environment (either virtual or bare metal), the build is done in four separate steps:

1. Prerequisite packages.  Mostly compilers, tools and libraries needed to compile everything else.
1. OpenResty system, including Nginx, LuaJIT, PCRE, etc.
1. Databases. Kong uses Posgres, Cassandra and Redis.  We have a handy setup with docker-compose to keep each on its container.
1. Kong itself.


### Prerequisites

These are the needed tools and libraries that aren't installed out of the box on Ubuntu and Fedora, respectively.  Just run one of these, either as root or sudo.

Ubuntu:

```
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

```
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

We have a build script that makes it easy to pull and compile specific versions of the needed components of the OpenResty system.  Currently these include OpenResty 1.15.8.2, OpenSSl 1.1.1d, LuaRocks 3.2.1 and PCRE 8.43;  the exact versions can also be found on the `.requirements` file of the main Kong repository (https://github.com/Kong/kong/blob/master/.requirements)

These commands don't have to be performed as root, since all compilation is done within a subdirectory, and installs everything in the target specified by the `-p` argument (here the `build` directory).

```
    git clone https://github.com/kong/openresty-build-tools

    cd openresty-build-tools

    ./kong-ngx-build -p build \
        --openresty 1.15.8.2 \
        --openssl 1.1.1d \
        --luarocks 3.2.1 \
        --pcre 8.43
```

After this task, we'd like to have the next steps use the built packages and for LuaRocks to install new packages inside this `build` directory.  For that, it's important to set the `$PATH` variable accordingly:

```
    export PATH=$HOME/path/to/kong/openresty-build-tools/build/openresty/bin:$HOME/path/to/kong/openresty-build-tools/build/openresty/nginx/sbin:$HOME/path/to/kong/openresty-build-tools/build/luarocks/bin:$PATH
    export OPENSSL_DIR=$HOME/path/to/kong/openresty-build-tools/build/openssl

    eval `luarocks path`
```

The `$OPENSSL_DIR` variable is needed when compiling Kong, to make sure it uses the correct version of OpenSSL.

You can add these lines to your `.profile` or `.bashrc` file.  Otherwise you could find yourself wondering where is everything!.


### Databases

The easiest way to handle these as a single group is via docker-compose.  It's also recommended to set your user as a [docker manager](https://docs.docker.com/install/linux/linux-postinstall/#manage-docker-as-a-non-root-user) to simplify the next steps.

Make sure the docker daemon is enabled and running: `sudo systemctl enable docker` and `sudo systemctl start docker`.  Verify that `docker ps` shows no errors.

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
    git checkout next
    make dev
```

Now run unit tests with `make test` and integration test with `make test-integration`.

Hack on!
