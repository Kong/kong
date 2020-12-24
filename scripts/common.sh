#!/usr/bin/env bash

ON_EXIT=("${ON_EXIT[@]}")
EXIT_RES=

function on_exit_fn {
  EXIT_RES=$?
  for cb in "${ON_EXIT[@]}"; do $cb || true; done
  # read might hang on ctrl-c, this is a hack to finish the script for real
  clear_exit
  exit $EXIT_RES
}

trap on_exit_fn EXIT SIGINT

function on_exit {
  ON_EXIT+=("$@")
}


function clear_exit {
  trap - EXIT SIGINT
}

