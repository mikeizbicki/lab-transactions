#!/bin/sh

# these lines ensure that any errors immediately kill the script and all children
set -e
trap "exit" INT TERM
trap "kill 0" EXIT

