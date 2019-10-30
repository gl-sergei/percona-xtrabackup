#
#
#

require_server_version_higher_than 5.7.10

. inc/keyring_file.sh

start_server

mysql -e "CREATE TABLE t (a INT) ENCRYPTION='y'" test
mysql -e "INSERT INTO t VALUES (1), (2), (3), (4)" test

innodb_wait_for_flush_all

mv $keyring_file ${keyring_file}.1

run_cmd_expect_failure $XB_BIN $XB_ARGS \
		       --backup --target-dir=$topdir/backup \
		       2> >(tee $topdir/backup.log)

if grep -q "xtrabackup got signal" $topdir/backup.log ; then
    die "xtrabackup crashed"
fi
