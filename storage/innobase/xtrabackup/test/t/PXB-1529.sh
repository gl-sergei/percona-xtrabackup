#
# Basic test of InnoDB temporary tablespace encryption support
#

require_server_version_higher_than 5.7.20

. inc/keyring_file.sh

start_server --secure-file-priv=$TEST_VAR_ROOT

vlog "Creating tables"

mysql test <<EOF &

CREATE TABLE resume (val INT);

DROP PROCEDURE IF EXISTS wait_for_resume;
delimiter //
CREATE PROCEDURE wait_for_resume()
BEGIN
	DECLARE x INT;
	SET x = 0;
	DELETE FROM resume;
	INSERT INTO resume VALUES (0);
	WHILE x <> 1 DO
		SELECT SLEEP(1);
		SELECT val INTO x FROM resume LIMIT 1;
	END WHILE;

END//
delimiter ;

CREATE TABLE t1 (c1 INT) ENCRYPTION='Y';

INSERT INTO t1 (c1) VALUES (1), (2), (3);
INSERT INTO t1 (c1) VALUES (10), (20), (30);

INSERT INTO t1 SELECT * FROM t1;
INSERT INTO t1 SELECT * FROM t1;

CREATE TEMPORARY TABLE t03 (a TEXT) ENGINE=InnoDB;
INSERT INTO t03 VALUES ('Curabitur laoreet, velit non interdum venenatis');

CREATE TEMPORARY TABLE t04 (a TEXT) ENGINE=InnoDB ROW_FORMAT=COMPRESSED;
INSERT INTO t04 VALUES ('Praesent tristique eros a tempus fringilla');


SELECT 'pause' INTO OUTFILE '$MYSQLD_TMPDIR/pause';

CALL wait_for_resume();

EOF

mysql_pid=$!

vlog "Waiting for pause"

while [[ ! -f $MYSQLD_TMPDIR/pause ]]; do
	sleep 1
done

ls -al $mysql_datadir $mysql_datadir/test

vlog "Starting backup"

xtrabackup --backup --target-dir=$topdir/backup \
	   --transition-key=123 \
	   --debug-sync="data_copy_thread_func" &

job_pid=$!
pid_file=$topdir/backup/xtrabackup_debug_sync

# Wait for xtrabackup to suspend
i=0
while [ ! -r "$pid_file" ]
do
    sleep 1
    i=$((i+1))
    echo "Waited $i seconds for $pid_file to be created"
done

xb_pid=`cat $pid_file`

vlog "Resuming mysql"

mysql test -e "UPDATE resume SET val = 1"

run_cmd wait $mysql_pid

mysql test <<EOF

CREATE TABLE t2 (c1 INT) ENCRYPTION='Y';

INSERT INTO t2 (c1) VALUES (1), (2), (3);
INSERT INTO t2 (c1) VALUES (10), (20), (30);

INSERT INTO t2 SELECT * FROM t2;
INSERT INTO t2 SELECT * FROM t2;

# create large enough table in order to make CREATE INDEX to use temporary table
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

CREATE INDEX t10_b ON t10 (b) ALGORITHM=COPY;
DROP INDEX t10_b ON t10 ALGORITHM=COPY;


CREATE TABLE qp11 (c1 INT) ENCRYPTION='Y';
INSERT INTO qp11 (c1) VALUES (1), (2), (3);
INSERT INTO qp11 (c1) VALUES (10), (20), (30);
INSERT INTO qp11 SELECT * FROM qp11;
INSERT INTO qp11 SELECT * FROM qp11;


CREATE TABLE qp12 (c1 INT) ENCRYPTION='Y';
INSERT INTO qp12 (c1) VALUES (1), (2), (3);
INSERT INTO qp12 (c1) VALUES (10), (20), (30);
INSERT INTO qp12 SELECT * FROM qp12;
INSERT INTO qp12 SELECT * FROM qp12;


CREATE TABLE qp13 (c1 INT) ENCRYPTION='Y';
INSERT INTO qp13 (c1) VALUES (1), (2), (3);
INSERT INTO qp13 (c1) VALUES (10), (20), (30);
INSERT INTO qp13 SELECT * FROM qp13;
INSERT INTO qp13 SELECT * FROM qp13;


EOF

# Resume xtrabackup
vlog "Resuming xtrabackup"
kill -SIGCONT $xb_pid

run_cmd wait $job_pid

record_db_state test

xtrabackup --prepare --target-dir=$topdir/backup --transition-key=123

stop_server

rm -rf $mysql_datadir

xtrabackup --copy-back --target-dir=$topdir/backup --transition-key=123

start_server

xtrabackup --backup --target-dir=$topdir/backup1 \
	   --transition-key=123

verify_db_state test

