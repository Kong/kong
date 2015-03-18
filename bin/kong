#!/bin/bash

# Setting Kong Home
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
export KONG_HOME="$(echo $SCRIPT_DIR | sed -e 's/\/[^\/]*$//')"

# Setting configuration path
if [ -f /etc/kong.yml ]; then
  export KONG_CONF=/etc/kong.yml
  printf "Giving priority to configuration stored at "$KONG_CONF" - To override use -c option\n"
else
  export KONG_CONF=$KONG_HOME/kong.yml
fi

# Setting nginx output path
nginx_output=$(lua -e "print(require('yaml').load(require('kong.tools.utils').read_file('$KONG_CONF')).output)")
if [ "$nginx_output" == "nil" ]; then
  export NGINX_TMP=$KONG_HOME/nginx_tmp
else
  export NGINX_TMP=$nginx_output
fi

PID=$NGINX_TMP/nginx.pid

#####################
# Utility functions #
#####################

function check_file_exists {
  if [ ! -f $1 ]; then
    printf "Can't find configuration file at: $1\n"
    exit 1
  fi
}

function real_path_func {
  if [ "$(uname)" == "Darwin" ]; then
    if ! hash realpath 2> /dev/null; then
      echo `perl -MCwd -e 'use Cwd "abs_path";$realfilepath = abs_path("$ARGV[0]");print "$realfilepath\n";' $1`
    else
      echo `realpath $1`
    fi
  else
    echo `readlink -f $1`
  fi
}

function print_error {
  printf "$1 $(tput setaf 1)[$2]\n$(tput sgr 0)"
}

function print_success {
  printf "$1 $(tput setaf 2)[$2]\n$(tput sgr 0)"
}

##############
# Operations #
##############

function show_help {
  printf "Usage: kong [OPTION]... {start|stop|restart}\n
\t-c    path to a kong configuration file. Default is: $KONG_CONF
\t-v    output version and exit
\t-h    show this message
\nCommands:\n
\tstart      start kong
\tstop       stop a running kong
\trestart    restart kong. Equivalent to executing 'stop' and 'start' in succession
\n"
}

function show_version {
  printf "Version: 0.0.1beta-1\n"
}

function start {
  if [ -f $PID ]; then
    if ps -p $(cat $PID) > /dev/null
    then
      print_error "Starting Kong" "ALREADY RUNNING"
      exit 1
    fi
  fi

  printf "configuration:   $KONG_CONF\nnginx container: $NGINX_TMP\n\n"

  mkdir -p $NGINX_TMP/logs &> /dev/null
  if [ $? -ne 0 ]; then
    printf "Cannot operate on $NGINX_TMP - Make sure you have the right permissions.\n\n"
    print_error "\nStarting Kong:" "ERROR"
    exit 1
  fi

  touch $NGINX_TMP/logs/error.log
  touch $NGINX_TMP/logs/access.log
  $KONG_HOME/scripts/config.lua -c $KONG_CONF -o $NGINX_TMP nginx
  nginx -p $NGINX_TMP -c $NGINX_TMP/nginx.conf

  if [ $? -eq 0 ]; then
    print_success "Starting Kong" "OK"
  else
    print_error "\nStarting Kong" "ERROR"
    error_file=`grep -e '^error_log' $NGINX_TMP/nginx.conf | grep -v syslog:server | grep -v stderr | awk '{print $2}'`
    if [ -n "$error_file" ]; then
      if [[ "$error_file" = /* ]]; then
        printf "Error logs: $error_file\n"
      else
        printf "Error logs: $NGINX_TMP/$error_file\n"
      fi
    fi
    exit 1
  fi
}

function stop {
  if [ ! -f $PID ]; then
    print_error "Stopping Kong" "NOT RUNNING"
    if [ "$1" = false ] ; then # $1 is true when it's part of a restart
      exit 1
    fi
  else
    kill $(cat $PID)
    print_success "Stopping Kong" "OK"
  fi
}

function restart {
  stop true
  start
}

######################
#  Argument parsing  #
######################

OPTIND=1 # Reset in case getopts has been used previously in the shell.
cmd=""

while getopts "h?vc:n:" opt; do
  case "$opt" in
    h|\?)
      show_help
      exit 0
      ;;
    v)
      show_version
      exit 0
      ;;
    c)
      KONG_CONF=$(real_path_func $OPTARG)
      ;;
  esac
done

shift $((OPTIND-1))

[ "$1" = "--" ] && shift

check_file_exists $KONG_CONF

case "$@" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    restart
    ;;
  *)
    show_help

esac

# End of file
