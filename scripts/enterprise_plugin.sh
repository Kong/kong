#!/usr/bin/env bash

# This is a temporary shell script, to avoid having unclean bash in the Makefile.

function globals {
  # Project related global variables
  local local_path
  local_path="$(dirname "$(realpath "$0")")"
  KONG_PATH=$(dirname "$(realpath "$local_path")")
  KONG_PLUGINS_EE_LOCATION=$KONG_PATH/plugins-ee
}

function usage {
  cat <<EOF
enterprise_plugin action [options...]
--------------------------------------------------
EOF

  cat <<EOF
Options:
  -h, --help                      display this help
Commands:
  install <plugin-name> Installs the specified plugin from the 'plugins-ee' directory.              b
  install-all           Install all enterprise plugins from the 'plugins-ee' directory.

                        --ignore-errors        ignore plugin installation errors.
  remove-all            Remove all enterprise plugins from the 'plugins-ee' directory.
  test <plugin-name>    Run lint and tests of the specified plugin.
  build-deps            Build all docker image dependencies found in plugin directories.
EOF
}

function install_plugin_ee {
  local plugin_name=$1
  if [ -z "$plugin_name" ]; then
    echo "Error: no plugin name specified."
    exit 1
  fi

  echo "Installing plugin: $(basename $plugin_name)"
  cd $KONG_PLUGINS_EE_LOCATION/$plugin_name
  luarocks make *.rockspec
  if [ $? -ne 0 ]; then
    exit 1
  fi
}

function install_all_plugins_ee {
  local ignore_errors=false
  while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
    --ignore-errors)
      ignore_errors=true
      ;;
    esac
    shift
  done

  for plugin_ee in $KONG_PLUGINS_EE_LOCATION/*; do
    if [ -d $plugin_ee ]; then
      echo "Installing plugin: $(basename $plugin_ee)"
      cd $plugin_ee
      luarocks make *.rockspec
      if [ $? -ne 0 -a $ignore_errors = false ]; then
        exit 1
      fi
    fi
  done
}

function test_plugin {
  local plugin_name=$1
  if [ -z "$plugin_name" ]; then
    echo "Error: no plugin name specified."
    exit 1
  fi

  local plugin_path=$KONG_PLUGINS_EE_LOCATION/$plugin_name
  if [ ! -d $plugin_path ]; then
    echo "Error: plugin '$plugin_name' not found in '$KONG_PLUGINS_EE_LOCATION/'."
    exit 1
  fi

  echo "Running lint and tests of: $plugin_name"
  pushd $plugin_path
  luacheck -v > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    # no local luacheck available, use Pongo
    KONG_IMAGE=$DOCKER_IMAGE_NAME pongo lint
    if [ $? -ne 0 ]; then
      pongo down
      exit 1
    fi
  else
    # use local Luacheck
    local lc_config
    if [ -f .luacheckrc ]; then
      lc_config=.luacheckrc
    else
      lc_config=$KONG_PATH/.luacheckrc
    fi
    luacheck -q --config="$lc_config" .
    if [ $? -ne 0 ]; then
      exit 1
    fi
  fi

  if [ -d ./spec ]; then
    KONG_IMAGE=$DOCKER_IMAGE_NAME pongo run -- --exclude-tags=flaky $PONGO_EXTRA_ARG
    err_code=$?
    mv report.html $XML_OUTPUT/report-$plugin_name.xml || true
    pongo down
    popd
    exit $err_code
  else
    echo "Skipping tests; no tests found for $plugin_name"
  fi
}

function build_deps {
  for plugin_dep in $KONG_PLUGINS_EE_LOCATION/*/.pongo/*; do
    if [ -d $plugin_dep -a -f $plugin_dep/Dockerfile ]; then
      local plugin_dep_name=$(basename $plugin_dep)
      echo "Building pongo dependency image: $plugin_dep_name"
      pushd $plugin_dep
      docker build -t $plugin_dep_name .
      if [ $? -ne 0 ]; then
        exit 1
      fi
      popd
    fi
  done
}

function remove_all_plugins_ee {
  for plugin_ee in $KONG_PLUGINS_EE_LOCATION/*; do
    if [ -d $plugin_ee ]; then
      echo "Removing plugin: `basename $plugin_ee`"
      package_name=$(sed -n 's/^package\s*=\s*"\(.*\)".*/\1/p' *.rockspec)
      cd $plugin_ee
      luarocks remove $package_name
    fi
  done
}

function main {
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  local action
  ! [[ $1 =~ ^- ]] && action=$1 && shift

  local unparsed_args=()
  while [[ $# -gt 0 ]]; do
    local key="$1"
    case $key in
    -h | --help)
      usage
      exit 0
      ;;
    *)
      unparsed_args+=("$1")
      ;;
    esac
    shift
  done

  if [[ -n "$action" ]]; then
    case $action in
    install)
      install_plugin_ee "${unparsed_args[@]}"
      ;;
    install-all)
      install_all_plugins_ee "${unparsed_args[@]}"
      ;;
    remove-all)
      remove_all_plugins_ee
      ;;
    test)
      test_plugin "${unparsed_args[@]}"
      ;;
    build-deps)
      build_deps
      ;;
    *)
      usage
      exit 1
      ;;
    esac
  else
    usage
    exit 1
  fi
}

globals
main "$@"
