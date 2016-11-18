#
# Bug 1641872: trailing / is missing when using changed page tracking
#

# when innodb-data-home-dir specified without trailing slash, xtrabackup
# was unable to use changed page tracking

require_xtradb

mkdir ${TEST_VAR_ROOT}/innohome

trap "rm -rf ${TEST_VAR_ROOT}/innohome" SIGINT SIGTERM EXIT

MYSQLD_EXTRA_MY_CNF_OPTS="
innodb-track-changed-pages=TRUE
innodb-data-home-dir=${TEST_VAR_ROOT}/innohome
"

start_server

$MYSQL $MYSQL_ARGS -e 'CREATE TABLE t1 (a INT)' test
$MYSQL $MYSQL_ARGS -e 'INSERT INTO t1 VALUES (1), (2), (3)' test

xtrabackup --backup --target-dir=$topdir/backup

shutdown_server
start_server

$MYSQL $MYSQL_ARGS -e 'INSERT INTO t1 VALUES (11), (12), (13)' test

$MYSQL $MYSQL_ARGS -e 'FLUSH CHANGED_PAGE_BITMAPS' test

xtrabackup --backup --target-dir=$topdir/backup1 --incremental-basedir=$topdir/backup

check_bitmap_inc_backup

