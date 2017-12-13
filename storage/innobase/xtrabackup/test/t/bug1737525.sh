#
# Test for encrypted general tablespaces
#

require_server_version_higher_than 5.7.19
require_xtradb

function insert_char()
{
	table=$1
	( for i in {1..1000} ; do
		echo "INSERT INTO ${table} VALUES (UUID());"
	done ) | mysql test
}

function insert_int()
{
	table=$1
	( for i in {1..1000} ; do
		echo "INSERT INTO ${table} VALUES ($i);"
	done ) | mysql test
}

function insert_int2()
{
	table=$1
	( for i in {1..1000} ; do
		echo "INSERT INTO ${table} VALUES ($i, $i);"
	done ) | mysql test
}

keyring_file=${TEST_VAR_ROOT}/keyring_file

start_server --early-plugin-load=keyring_file.so --keyring-file-data=$keyring_file

mysql -e "CREATE TABLESPACE ts_encrypted ADD DATAFILE 'ts_encrypted.ibd' ENCRYPTION='Y' ENGINE='InnoDB'" test
mysql -e "CREATE TABLESPACE ts_unencrypted ADD DATAFILE 'ts_unencrypted.ibd' ENGINE='InnoDB'" test
mysql -e "CREATE TABLESPACE ts_encrypted_new ADD DATAFILE 'ts_encrypted_new.ibd' ENCRYPTION='Y' ENGINE='InnoDB'" test

mysql -e "CREATE TABLE t3 (a TEXT) TABLESPACE ts_encrypted ENCRYPTION='Y' ENGINE='InnoDB'" test
insert_char t3

mysql -e "CREATE TABLE pt2 (a INT NOT NULL, PRIMARY KEY(a)) \
	ENGINE=InnoDB TABLESPACE ts_encrypted ENCRYPTION='y' \
	PARTITION BY RANGE (a) PARTITIONS 3 ( \
		PARTITION p1 VALUES LESS THAN (20), \
		PARTITION p2 VALUES LESS THAN (40) TABLESPACE innodb_file_per_table, \
		PARTITION p3 VALUES LESS THAN (60) TABLESPACE ts_encrypted_new)" test

mysql -e "ALTER TABLE pt2 ADD PARTITION (PARTITION p4 VALUES LESS THAN (80000) TABLESPACE ts_encrypted_new)" test

insert_int pt2

mysql -e "CREATE TABLE spt2 (a INT NOT NULL, b INT) \
	ENGINE=InnoDB TABLESPACE ts_encrypted ENCRYPTION='y' \
	PARTITION BY RANGE (a) PARTITIONS 3 SUBPARTITION BY KEY (b) ( \
		PARTITION p1 VALUES LESS THAN (20) ( \
			SUBPARTITION p11 TABLESPACE ts_encrypted, \
			SUBPARTITION p12 TABLESPACE innodb_file_per_table, \
			SUBPARTITION p13 TABLESPACE ts_encrypted_new), \
		PARTITION p2 VALUES LESS THAN (40) TABLESPACE innodb_file_per_table ( \
			SUBPARTITION p21 TABLESPACE ts_encrypted, \
			SUBPARTITION p22 TABLESPACE innodb_file_per_table, \
			SUBPARTITION p23 TABLESPACE ts_encrypted_new), \
		PARTITION p3 VALUES LESS THAN (60) TABLESPACE ts_encrypted_new ( \
			SUBPARTITION p31 TABLESPACE ts_encrypted, \
			SUBPARTITION p32 TABLESPACE innodb_file_per_table, \
			SUBPARTITION p33 TABLESPACE ts_encrypted_new))" test

mysql -e "ALTER TABLE spt2 ADD PARTITION (PARTITION p5 VALUES LESS THAN (140) ( \
			SUBPARTITION p51 TABLESPACE ts_encrypted, \
			SUBPARTITION p52 TABLESPACE ts_encrypted_new, \
			SUBPARTITION p53 TABLESPACE ts_encrypted_new))" test

mysql -e "ALTER TABLE spt2 ADD PARTITION (PARTITION p6 VALUES LESS THAN (15000) TABLESPACE ts_unencrypted ( \
			SUBPARTITION p61 TABLESPACE ts_encrypted, \
			SUBPARTITION p62 TABLESPACE ts_encrypted_new, \
			SUBPARTITION p63 TABLESPACE ts_encrypted_new))" test

insert_int2 spt2

xtrabackup --backup --target-dir=$topdir/backup \
	   --keyring-file-data=$keyring_file

record_db_state test

xtrabackup --prepare --target-dir=$topdir/backup \
	   --keyring-file-data=$keyring_file

stop_server

rm -rf $mysql_datadir

xtrabackup --copy-back --target-dir=$topdir/backup

start_server --early-plugin-load=keyring_file.so --keyring-file-data=$keyring_file

verify_db_state test
