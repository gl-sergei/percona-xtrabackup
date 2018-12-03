
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

( for i in {1..1000} ; do
  echo "INSERT INTO sbtest1 (k, c, pad) VALUES (FLOOR(RAND() * 1000000), UUID(), UUID());"
done ) | mysql test

for i in {2..10} ; do
  mysql -e "INSERT INTO sbtest$i SELECT * FROM sbtest1" test
done

mysql test <<EOF
CREATE TABLE t10 (a INT AUTO_INCREMENT PRIMARY KEY, b INT);
INSERT INTO t10 (b) VALUES (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000));
INSERT INTO t10 (b) VALUES (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000));
INSERT INTO t10 (b) VALUES (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000));
INSERT INTO t10 (b) VALUES (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000));
INSERT INTO t10 (b) VALUES (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000));
INSERT INTO t10 (b) VALUES (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000));
INSERT INTO t10 (b) VALUES (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000));
INSERT INTO t10 (b) VALUES (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000));
INSERT INTO t10 (b) VALUES (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000));
INSERT INTO t10 (b) VALUES (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000)), (FLOOR(RAND() * 10000));
INSERT INTO t10 (b) SELECT b FROM t10;
INSERT INTO t10 (b) SELECT b FROM t10;
INSERT INTO t10 (b) SELECT b FROM t10;
INSERT INTO t10 (b) SELECT b FROM t10;
INSERT INTO t10 (b) SELECT b FROM t10;
EOF

( while true ; do
  ${MYSQL} ${MYSQL_ARGS} test -e 'CREATE INDEX t10_b ON t10 (b);' 1>/dev/null 2>/dev/null
  # sleep 1
  ${MYSQL} ${MYSQL_ARGS} test -e 'DROP INDEX t10_b ON t10;' 1>/dev/null 2>/dev/null
  # sleep 1
  ${MYSQL} ${MYSQL_ARGS} test -e 'CREATE INDEX t10_b ON t10 (b) ALGORITHM=COPY;' 1>/dev/null 2>/dev/null
  # sleep 1
  ${MYSQL} ${MYSQL_ARGS} test -e 'DROP INDEX t10_b ON t10 ALGORITHM=COPY;' 1>/dev/null 2>/dev/null
  # sleep 1
done ) &
jid2=$!

sleep 2

xtrabackup --lock-ddl --backup --target-dir=$topdir/backup

rm -rf ~/.tmp/bak
cp -av $topdir/backup ~/.tmp/bak

stop_server

xtrabackup --prepare --target-dir=$topdir/backup

rm -rf $mysql_datadir
xtrabackup --copy-back --target-dir=$topdir/backup

start_server

if mysql -e 'CHECK TABLE t10' test | grep -i 'Corrupt' ; then
  die "t10 is corrupt"
fi
