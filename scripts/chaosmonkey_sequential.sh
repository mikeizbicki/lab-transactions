#!/bin/sh

# these lines ensure that any errors immediately kill the script and all children
set -e
trap "exit" INT TERM
trap "kill 0" EXIT

# get the url from the command line parameters
url="$1"
if [ -z "$url" ]; then
    echo "ERROR: you must enter a database url to connect to for the test"
    fail
fi

# randomly spawn and kill processes
for i in $(seq 1 20); do
    echo "iteration $i"
    python3 scripts/random_transfers.py $url --num_transfers=9999999999 &
    pid=$!
    sleep 1
    kill $pid
done

