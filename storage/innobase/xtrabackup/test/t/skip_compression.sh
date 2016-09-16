
start_server --innodb_file_format=Barracuda

${MYSQL} ${MYSQL_ARGS} -e "CREATE TABLE t (a INT(11) DEFAULT NULL, \
 number INT(11) DEFAULT NULL) ENGINE=INNODB\
 ROW_FORMAT=compressed KEY_BLOCK_SIZE=8" test
${MYSQL} ${MYSQL_ARGS} -e "INSERT INTO t VALUES (1, 1)" test



rm -rf $topdir/backup/*
xtrabackup --backup --target-dir=$topdir/backup --compress --skip-compress-page-compressed-tables
test -f $topdir/backup/test/t.ibd || die "$topdir/backup/test/t.ibd is not found"

rm -rf $topdir/backup/*
xtrabackup --backup --target-dir=$topdir/backup --compress --stream=xbstream --skip-compress-page-compressed-tables | xbstream -x -C $topdir/backup
test -f $topdir/backup/test/t.ibd || die "$topdir/backup/test/t.ibd is not found"



rm -rf $topdir/backup/*
xtrabackup --backup --target-dir=$topdir/backup --compress --compress-page-compressed-tables
test -f $topdir/backup/test/t.ibd.qp || die "$topdir/backup/test/t.ibd.qp is not found"

rm -rf $topdir/backup/*
xtrabackup --backup --target-dir=$topdir/backup --compress --stream=xbstream --compress-page-compressed-tables | xbstream -x -C $topdir/backup
test -f $topdir/backup/test/t.ibd.qp || die "$topdir/backup/test/t.ibd.qp is not found"



rm -rf $topdir/backup/*
xtrabackup --backup --target-dir=$topdir/backup --compress
test -f $topdir/backup/test/t.ibd.qp || die "$topdir/backup/test/t.ibd.qp is not found"

rm -rf $topdir/backup/*
xtrabackup --backup --target-dir=$topdir/backup --compress --stream=xbstream | xbstream -x -C $topdir/backup
test -f $topdir/backup/test/t.ibd.qp || die "$topdir/backup/test/t.ibd.qp is not found"
