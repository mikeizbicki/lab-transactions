#!/bin/sh

set -e

sum_balances=$(docker-compose exec -T pg psql -X -A -w -t <<EOF
SELECT sum(balance) FROM balances;
EOF
)

echo $sum_balances

if [ 0 != "$sum_balances" ]; then
    echo FAIL
    false
else
    echo PASS
fi
