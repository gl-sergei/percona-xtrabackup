############################################################################
# Common code for xb_*.sh local backup tests.
# Expects the following variables to be set appropriately before
# including:
#
# Optionally the following variables may be set:
#   xtrabackup_option:  additional options to be passed to xtrabackup.
#   data_decrypt_cmd: command used to decrypt data
#   data_decompress_cmd: command used to decompress data
############################################################################

. inc/common.sh

start_server --innodb_file_per_table

load_dbase_schema sakila
load_dbase_data sakila

xtrabackup_options=${xtrabackup_options:-""}
xtrabackup_options="${xtrabackup_options} --no-timestamp"

[ -d ${mysql_datadir}/test ] || mkdir ${mysql_datadir}/test

# Take backup
backup_dir=${topdir}/backup
xtrabackup $xtrabackup_options --backup --target-dir=$backup_dir
vlog "Backup created in directory $backup_dir"

stop_server
# Remove datadir
rm -r $mysql_datadir

# Restore sakila
vlog "Applying log"
cd $backup_dir
if [ -n "${data_decrypt_cmd:=""}" ] || [ -n "${data_decompress_cmd:=""}" ]; then 
  vlog "###################################"
  vlog "# DECRYPTING AND/OR DECOMPRESSING #"
  vlog "###################################"
  test -n "${data_decrypt_cmd:=""}" && run_cmd bash -c "$data_decrypt_cmd"
  test -n "${data_decompress_cmd:-""}" && run_cmd bash -c "$data_decompress_cmd";
fi
cd - >/dev/null 2>&1
vlog "###########"
vlog "# PREPARE #"
vlog "###########"
xtrabackup --prepare --target-dir=$backup_dir
mkdir -p $mysql_datadir
vlog "###########"
vlog "# RESTORE #"
vlog "###########"
xtrabackup --copy-back --target-dir=$backup_dir

start_server
# Check sakila
run_cmd ${MYSQL} ${MYSQL_ARGS} -e "SELECT count(*) from actor" sakila

########################################################################
# Bug #1217426: Empty directory is not backed when stream is used
########################################################################
run_cmd ${MYSQL} ${MYSQL_ARGS} -e "CREATE TABLE t(a INT)" test
run_cmd ${MYSQL} ${MYSQL_ARGS} -e "SELECT * FROM t" test
