#
# PXB-1918: Minor issues in PXB help options
#

# check that --incremental-* options are mutually exclusive

start_server

xtrabackup --backup --target-dir=$topdir/backup

run_cmd_expect_failure ${XB_BIN} ${XB_ARGS} --backup \
                       --incremental-basedir=$topdir/backup \
		       --incremental-lsn=2
run_cmd_expect_failure ${XB_BIN} ${XB_ARGS} --backup \
                       --incremental-basedir=$topdir/backup \
		       --incremental-history-name=2
run_cmd_expect_failure ${XB_BIN} ${XB_ARGS} --backup \
                       --incremental-basedir=$topdir/backup \
		       --incremental-history-uuid=2

run_cmd_expect_failure ${XB_BIN} ${XB_ARGS} --backup \
                       --incremental-lsn=1 \
		       --incremental-history-name=2
run_cmd_expect_failure ${XB_BIN} ${XB_ARGS} --backup \
                       --incremental-lsn=1 \
		       --incremental-history-uuid=2

run_cmd_expect_failure ${XB_BIN} ${XB_ARGS} --backup \
                       --incremental-history-name=1 \
		       --incremental-history-uuid=2

COUNT=$(grep -E -c -- "--[^ ]+ and --[^ ]+ are mutually exclusive" $OUTFILE)
echo $COUNT
if [ "$COUNT" != "6" ] ; then
    die "count is $COUNT"
fi
