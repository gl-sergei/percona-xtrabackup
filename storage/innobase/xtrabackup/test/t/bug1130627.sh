########################################################################
# Bug #1130627: Can't backup individual partitions
########################################################################

. inc/common.sh
. inc/ib_part.sh

MYSQLD_EXTRA_MY_CNF_OPTS="innodb-file-per-table"

start_server

require_partitioning

run_cmd $MYSQL $MYSQL_ARGS test <<EOF
CREATE TABLE t_innodb (
  i INT NOT NULL AUTO_INCREMENT,
  c CHAR(10) DEFAULT NULL,
  PRIMARY KEY (i)
) ENGINE=InnoDB
/*!50100 PARTITION BY HASH (i)
PARTITIONS 10 */;

CREATE TABLE t_myisam (
  i INT NOT NULL AUTO_INCREMENT,
  c CHAR(10) DEFAULT NULL,
  PRIMARY KEY (i)
) ENGINE=MyISAM
/*!50100 PARTITION BY HASH (i)
PARTITIONS 10 */;
EOF

force_checkpoint

# Test that specifying partitions with --include works
xtrabackup --backup --include='^test.*#P#p5' --target-dir=$topdir/backup
xtrabackup --prepare --target-dir=$topdir/backup

file_cnt=`ls $topdir/backup/test | wc -l`

test "$file_cnt" -eq 3

test -f $topdir/backup/test/t_innodb#P#p5.ibd
test -f $topdir/backup/test/t_myisam#P#p5.MYD
test -f $topdir/backup/test/t_myisam#P#p5.MYI

rm -rf $topdir/backup

# Test that specifying partitions with --databases works

xtrabackup --backup \
    --databases='test.t_myisam#P#p5 test.t_innodb#P#p5' --target-dir=$topdir/backup
xtrabackup --prepare --target-dir=$topdir/backup

test "$file_cnt" -eq 3
test -f $topdir/backup/test/t_innodb#P#p5.ibd
test -f $topdir/backup/test/t_myisam#P#p5.MYD
test -f $topdir/backup/test/t_myisam#P#p5.MYI

rm -rf $topdir/backup

# Test that specifying partitions with --tables-file works
cat >$topdir/tables_file <<EOF
test.t_myisam#P#p5
test.t_innodb#P#p5
EOF
xtrabackup --backup --tables-file=$topdir/tables_file --target-dir=$topdir/backup
xtrabackup --preapre --target-dir=$topdir/backup

test "$file_cnt" -eq 3
test -f $topdir/backup/test/t_myisam#P#p5.MYD
test -f $topdir/backup/test/t_myisam#P#p5.MYI

rm -rf $topdir/backup
