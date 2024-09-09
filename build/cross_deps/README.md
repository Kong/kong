# Dependencies for cross build

When cross building Kong (the target architecture is different from the host),
we need to build some extra dependencies to produce headers and dynamic libraries
to let compiler and linker work properly.

Following are the dependencies:
- libxcrypt
- libyaml
- zlib

Note that the artifacts of those dependencies are only used during build time,
they are not shipped together with our binary artifact (.deb, .rpm or docker image etc).

We currently do cross compile on following platforms:
- Amazonlinux 2
- Amazonlinux 2023
- Ubuntu 18.04 (Version 3.4.x.x only)
- Ubuntu 22.04
- Ubuntu 24.04
- RHEL 9
- Debian 12

As we do not use different versions in different distros just for simplicity, the version
of those dependencies should remain the lowest among all distros originally shipped, to
allow the produced artifacts has lowest ABI/API to be compatible across all distros.