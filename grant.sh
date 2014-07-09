#!/usr/bin/env bash
set -e
die() {
    ret="$1";shift;echo "${@}";if [ "x${ret}" != "x0" ];then exit 1;fi
}
db=$1
user="${2:-"${db}_owners"}"
echo "GRANT ALL PRIVILEGES ON DATABASE ${db} TO ${user};"| su postgres -c psql
die "${?}" grant1
echo "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${user};"| su postgres -c "psql -d \"${db}\""
die "${?}" grant2
echo "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${user};"| su postgres -c "psql -d \"${db}\""
die "${?}" grant3
echo "GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${user};"| su postgres -c "psql -d \"${db}\""
die "${?}" grant4
