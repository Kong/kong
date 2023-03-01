#!/usr/bin/env sh

# strict mode(-ish)
set -eu
IFS="$(printf '\t\n')"

if [ -n "${VERBOSE:-}" ]; then
  set -x
fi

install_from_github() {
  item="${1:-}" version='' owner_repo='' filename='' work=''

  version="$(eval "echo \"\$${item}_version\"")"

  if [ "$version" = "latest" ]; then
    version='latest'
  else
    version="v${version}"
  fi

  case "_${item}" in
  _yq)
    owner_repo="mikefarah/yq"
    filename="yq_${os}_${arch}"
    ;;
  _rootlesskit)
    owner_repo="rootless-containers/rootlesskit"
    filename="rootlesskit-${formal_arch}.tar.gz"
    ;;
  _bazelisk)
    owner_repo="bazelbuild/bazelisk"
    filename="bazelisk-linux-${arch}"
    ;;
  _git)
    owner_repo="git/git"
    filename="${version}.tar.gz"
    ;;
  esac

  if [ "$version" = "latest" ]; then
    url="https://github.com/${owner_repo}/releases/latest/download/${filename}"
  else
    url="https://github.com/${owner_repo}/releases/download/${version}/${filename}"
  fi

  if ! curl --fail -sSLI "$url" >/dev/null 2>&1; then
    url="https://github.com/${owner_repo}/archive/refs/tags/${filename}"
    if ! curl --fail -sSLI "$url" >/dev/null 2>&1; then
      echo "neither release nor tag URL worked for ${owner_repo}"
      exit 2
    fi
  fi

  repo="$(echo "$owner_repo" | cut -d'/' -f2)"

  if test -x "${bin_install_path}/${repo}"; then
    echo "${1} already seems to be here"
  fi

  case "_${filename}" in
  _*.tar.gz)
    work="$(mktemp -d)"
    curl -sSL "$url" -o "${work}/${filename}"

    dirs="$(tar -tvf "${work}/${filename}" | grep -cE '^d' || true)"

    if [ "$dirs" = 0 ]; then
      tar -C "$bin_install_path" -xzvf "${work}/${filename}"
    else
      echo "tarball contains directories, leaving at: ${work}/${filename}"
      return 0
    fi
    ;;
  _*)
    curl -sSL "$url" -o "${bin_install_path}/${repo}"
    ;;
  esac

  # shellcheck disable=SC2086
  ${_g}chmod -c a+x "${bin_install_path}/"${repo}*
}

install_build_tools() {
  case "_${os}-${packager}" in
  _linux-apt)
    cache_apt_refresh

    ${_sudo} apt-get install -y \
      wget \
      curl \
      build-essential \
      m4 \
      autoconf

    ;;
  _linux-yum)
    sed -i -e 's@keepcache=0@keepcache=1@' /etc/yum.conf || true
    echo 'keepcache=1' >> /etc/dnf/dnf.conf || true

    ${_sudo} yum check-update -y || true

    # stick with whatever kernel we have currently
    ${_sudo} yum groupinstall -y \
      --exclude='kernel-devel*' \
      --exclude='systemtap*' \
      --exclude='subversion' \
      'Development Tools'

    ${_sudo} yum install -y --skip-broken \
      curl \
      gzip \
      patch \
      tar \
      wget \
      which
    ;;

  _- | _*)
    echo "unsure how to build for os ${os} and package manager ${packager}"
    ;;
  esac

  install_from_github 'rootlesskit'
  install_from_github 'bazelisk'
  install_from_github 'yq'

  ln -sfv "${bin_install_path}/bazelisk" "${bin_install_path}/bazel"
}

install_build_tools_git() {
  if git --version 2>&1 | grep -qs "$git_version"; then
    return 0
  fi

  tarball_path="$(install_from_github git | tail -n1 | cut -d':' -f2 | xargs)"
  work="$(dirname "$tarball_path")"

  cd "$work"

  if ! test -d "git-${git_version}"; then
    tar -xf ./*"${git_version}"*.tar.gz
  fi

  cd "git-${git_version}"
  make configure
  ./configure --prefix="$(dirname "$bin_install_path")"
  make "-j$(nproc)"
  make install

  cd "$og_pwd"
}

install_build_dependencies() {
  case "_${os}-${packager}" in
  _linux-apt)
    cache_apt_refresh

    # ${_sudo} apt-get install -y \
    #   libyaml-dev \
    #   valgrind \
    #   libprotobuf-dev
    ;;
  _linux-yum)
    ${_sudo} yum check-update -y || true

    ${_sudo} yum install -y --skip-broken \
      curl-devel \
      expat-devel \
      gettext-devel \
      libyaml-devel \
      openssl-devel \
      perl-CPAN \
      perl-devel \
      zlib-devel \
      valgrind-devel

    ;;
  _- | _*)
    echo "unsure how to build for os ${os} and package manager ${packager}"
    ;;
  esac

  eval "$(
    grep -E -A 10 "kong_${nfpm_target}.," BUILD.bazel | grep 'RPM_EXTRA' |
      sed -e 's#"\(.*\)": "\(.*\)",#export \1=\2#g'
  )"

  nfpm_packages="$(
    eval "echo \"$(
      yq -P ".overrides.${package}.depends" <build/package/nfpm.enterprise.yaml |
        cut -d' ' -f2 | sed -e 's^-devel^^g' | sort -u |
        sed -e 's#${\(.*\)}#${\1:-}#g'
    )\""
  )"

  echo "$nfpm_packages" | xargs -t -I^ yum install -y --skip-broken ^ ^-devel

  cmake_prefix='/opt/cmake'
  mkdir -pv "$cmake_prefix"

  cd "$cmake_prefix"

  curl -sSL -O "https://github.com/Kitware/CMake/releases/download/v${cmake_version}/cmake-${cmake_version}-${os}-${formal_arch}.sh"
  ${_g}chmod -c a+x ./cmake*.sh

  # shellcheck disable=SC2211
  ./cmake*.sh --skip-license --prefix=/opt/cmake
  ln -sfv /opt/cmake/bin/* "${bin_install_path}/"

  # GHA seems to pass the runner's HOME env into the container and rustup gets
  # mad about it; explicitly set HOME before running rustup
  export HOME="$(getent passwd $(whoami) | cut -d':' -f6)"

  curl https://sh.rustup.rs -sSf | sh -s -- -y
  ln -sfv ${HOME}/.cargo/bin/* "${bin_install_path}/"
  rustup install stable
  rustup default stable
}

main() {
  # consumed via eval in install_from_github()
  # shellcheck disable=SC2034
  rootlesskit_version="${ROOTLESSKIT_VERSION:-1.1.0}"
  # shellcheck disable=SC2034
  bazelisk_version="${BAZELISK_VERSION:-1.15.0}"
  # shellcheck disable=SC2034
  yq_version="${YQ_VERSION:-latest}"
  cmake_version="${CMAKE_VERSION:-3.25.2}"
  git_version="${GIT_VERSION:-2.39.0}"

  bin_install_path='/opt/tools/bin'
  mkdir -pv "$bin_install_path"

  og_pwd="$(pwd)"

  # shellcheck disable=SC2016
  echo "PATH=${bin_install_path}:\$PATH" > /etc/profile.d/path-tools.sh

  # shellcheck source=/dev/null
  . "/etc/profile.d"/path-tools.sh

  case "_$(uname -m)" in
  _aarch64 | _arm64)
    arch='arm64'
    formal_arch='aarch64'
    # docker_arch='arm64v8'
    ;;
  _amd64 | _x86_64)
    arch='amd64'
    formal_arch='x86_64'
    # docker_arch='amd64'
    ;;
  esac

  case "_$(uname -s)" in
  _Linux)
    os='linux'
    # docker_os='linux'
    packager=''
    package=''

    nfpm_target=''
    if grep -qs 'Amazon' /etc/os-release; then
      nfpm_target='aws2'
      if grep -qsi '2022' /etc/os-release; then
        nfpm_target='aws2022'
      fi
    fi

    if grep -qsi 'CentOS-7' /etc/os-release; then
      nfpm_target='el7'
    fi

    if grep -qsi 'Red Hat Enterprise Linux 8' /etc/os-release; then
      nfpm_target='el8'
    fi

    # order matters
    for manager in apk apt yum dnf microdnf brew; do
      if command -v "$manager" >/dev/null 2>&1; then
        packager="$manager"
        case "_${packager}" in
        _apt)
          package='deb'
          ;;
        _yum | _dnf | _microdnf)
          package='rpm'
          ;;
        esac
        break
      fi
    done
    ;;
  _Darwin)
    os='darwin'
    # docker_os='darwin'
    ;;
  esac

  _g=''
  if [ "$os" = 'darwin' ]; then
    _g='g'
  fi

  _sudo=''
  # if command -v sudo >/dev/null 2>&1; then
  #   _sudo='sudo'
  # fi

  cache_apt_refresh() {
    age='300'
    stamp="$(stat -c %Y '/var/lib/apt/lists/partial' || true 2>/dev/null)"
    now="$("${_g}date" +%s)"
    if [ "${stamp:-0}" -le $((now - age)) ]; then
      echo "refreshing stale apt cache (older than ${age}s/$((age / 60))m)"
      ${_sudo} apt-get update -y
      ${_sudo} touch '/var/lib/apt/lists/partial'
    fi
  }

  install_build_tools
  install_build_dependencies

  # git compile needs zlib-devel installed via install_build_dependencies()
  # install_build_tools_git

  #   bazel info --show_make_env

  missing=''
  for tool in cmake git yq rootlesskit bazel cargo; do
    _which="$(which "$tool" || true)"
    if [ -z "$_which" ]; then
      missing="${missing} ${tool}"
    fi
    echo "${tool}: ($(which "$tool" || true)) $($tool --version)"
  done

  if [ -n "$missing" ]; then
    echo "missing tool(s): ${missing}"
    exit 1
  fi
}

main
