#
# PXB-1694: ALTER TABLE ... ALGORITHM=COPY causing prepare to fail
#

MYSQLD_EXTRA_MY_CNF_OPTS="
innodb_page_size=64k
"

start_server

for i in {1..10} ; do
mysql test <<EOF
CREATE TABLE sbtest$i (
  id INT NOT NULL AUTO_INCREMENT,
  k INT NOT NULL,
  c VARCHAR(120) NOT NULL,
  pad VARCHAR(60) NOT NULL,
  PRIMARY KEY (id),
  KEY k_1 (k)
) ENGINE=InnoDB;
EOF
done

( for i in {1..10000} ; do
  echo "INSERT INTO sbtest1 (k, c, pad) VALUES (FLOOR(RAND() * 1000000), UUID(), UUID());"
done ) | mysql test

for i in {2..10} ; do
  mysql -e "INSERT INTO sbtest$i SELECT * FROM sbtest1" test
done

mysql -e "SELECT SUM(k) FROM sbtest5" test > $topdir/sum

( while true ; do
  ${MYSQL} ${MYSQL_ARGS} test -e 'CREATE INDEX t10_c ON sbtest5 (c);' 1>/dev/null 2>/dev/null
  # sleep 1
  ${MYSQL} ${MYSQL_ARGS} test -e 'DROP INDEX t10_c ON sbtest5;' 1>/dev/null 2>/dev/null
  # sleep 1
  ${MYSQL} ${MYSQL_ARGS} test -e 'CREATE INDEX t10_c ON sbtest5 (c) ALGORITHM=COPY;' 1>/dev/null 2>/dev/null
  # sleep 1
  ${MYSQL} ${MYSQL_ARGS} test -e 'DROP INDEX t10_c ON sbtest5 ALGORITHM=COPY;' 1>/dev/null 2>/dev/null
  # sleep 1
done ) &

for i in {1..30} ; do
  rm -rf $topdir/backup
  xtrabackup --lock-ddl --backup --target-dir=$topdir/backup
  xtrabackup --prepare --target-dir=$topdir/backup
done

stop_server

rm -rf $mysql_datadir

xtrabackup --copy-back --target-dir=$topdir/backup

start_server

diff -u $topdir/sum <(mysql -e "SELECT SUM(k) FROM sbtest5" test)
