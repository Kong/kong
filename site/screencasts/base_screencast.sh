#!/bin/bash

function extract_id {
  name=$(echo $1 | pcregrep -o1 -i '.*"'$2'":"([\w\-]+).*')
  echo $name
}

function slow_echo {
  delay=$2
  if [ -z "$delay" ]
  then
    delay=0.1; # Default delay
  fi

  val="\n$1"
  skip_next=false
  for (( i=0; i<${#val}; i++ )); do
    char=${val:$i:1}
    next_char=${val:$i+1:1}
    if [ "$skip_next" == false ] ; then
      if [ "$char" == "\\" ] && [ "$next_char" == "n" ]
      then
        printf "\nlocalhost:tmp kong$ "
        skip_next=true
      else
        skip_next=false
        printf "$char"
      fi
      sleep $delay
    else
      skip_next=false
    fi
  done
}

function exec_cmd {
  slow_echo "\n$1" 0
  echo
  eval $1
}