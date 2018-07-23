#!/usr/bin/env bash

make dev
chmod -R 777 /kong/
/kong/bin/kong prepare
/kong/bin/kong migrations up && tail -f /dev/null