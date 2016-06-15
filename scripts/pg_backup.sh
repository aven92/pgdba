#!/bin/env bash

# ########################################################################
# PostgreSQL backup program
# License: PostgreSQL DBA
# Version: 1.0
# Authors: aven
# ########################################################################

declare -r PROGDIR="$(cd $(dirname $(readlink -f $0)) && pwd)"
declare -r PROGNAME="$(basename $(readlink -f $0))"

# PostgreSQL bin path and omnipitr bin path
declare -x -r PITR_BIN='/opt/omnipitr/bin'
declare -x -r PITR_DIR='/data/omnipitr'
declare -x -r PGBIN='/opt/pgsql/bin'

# the directory for the example is $path/postgresql/{data,backup,backup_remote,xlog_archive,scripts}
# current script in $path/postgresql/scripts
declare -x -r PGDATA="$PROGDIR/../data"
declare -x -r XLOG_ARCHIVE="$PROGDIR/../arclog"
declare -x -r BACKUP_LOCAL="$PROGDIR/../backup"
declare -x -r BACKUP_REMOTE="$PROGDIR/../rbackup"

# backup connection
declare -x -r MASTER_HOST=''
declare -x -r MASTER_USER='db_backup'
declare -x -r MASTER_PORT='5432'
declare -x -r PGPASSWORD=''

# error mail
declare -x -r ERROR_MAIL='sqldba@zhaopin.com.cn'

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH

# ##########################################################
# usage of this script
# ##########################################################
usage() {
	cat <<- EOF

	usage: $PROGNAME [usrions]

	OPTIONS:
	    -t, --backup-tool=pg_basebackup             specify backup tool (pg_basebackup or omnipitr), default pg_basebackup
	    -t, --backup-mode=auto                      specify backup mode (auto or local), default auto
	    -k, --keep-days=days                        keep days of backup archive in local, default keep all
	    -h, --help                                  usage of this program

	Examples:
	    $PROGNAME
	    $PROGNAME -m local
	    $PROGNAME -k 3
	    $PROGNAME -t pg_basebackup
	    $PROGNAME -t pg_basebackup -m auto -k 3

	EOF
}

# ##########################################################
# check whether backup server
# ##########################################################
is_backup_server() {
	local backup_server="$($PGBIN/psql -h $MASTER_HOST -U $MASTER_USER -d sqldba -A -t -c 'select client_addr from pg_stat_repl order by sync_priority desc, client_addr desc limit 1;')"
	local local_ips="$(ip a show up \
	    | awk -F'[ ]+|/' '/inet /{print $3}' \
	    | grep -v '127.0.0.1')"
	local is_slave="$("$PGBIN"/psql -U "$MASTER_USER" -d template1 -p "$MASTER_PORT" -A -t -c 'select pg_is_in_recovery();')"
	local backup_flag='0'

	for ip in $local_ips; do
	    if [[ -n "$backup_server" ]] && [[ "$ip" == "$backup_server" ]]; then
	        backup_flag='1'
	    break
	    elif [[ -z "$backup_server" ]]; then
	        backup_flag='2'
	    break
	    else
	        backup_flag='0'
	    continue
	    fi
	done

	if (( "$backup_flag" == "0" )); then
	    exit 0
	elif (( "$backup_flag" == "2" )) && [[ "$is_slave" == "t" ]]; then
	    exit 0
	fi
}

# ##########################################################
# use omnipitr backup in master
# ##########################################################
omnipitr_backup_master() {
	local is_in_backup="$($PGBIN/psql -h $MASTER_HOST -U $MASTER_USER -d template1 -A -t -c 'select pg_is_in_backup();')"
	local today="$(date +%Y%m%d)"
	local backup_dir="$BACKUP_LOCAL/$today"

	if [[ "$is_in_backup" == "t" ]]; then
	    exit 1
	fi

	mkdir -p "$backup_dir"

	$PITR_BIN/omnipitr-backup-master --host $MASTER_HOST \
	    --username "$MASTER_USER" \
	    --database template1 \
	    --port "$MASTER_PORT" \
	    --data-dir "$PGDATA" \
	    --xlogs "$XLOG_ARCHIVE" \
	    --pgcontroldata-path "$PGBIN"/pg_controldata \
	    --psql-path "$PGBIN"/psql \
	    --dst-local "$backup_dir" \
	    --log "$backup_dir"/omnipitr_backup_"$today".log \
	    --pid-file "$PITR_DIR"/pitr-backup-slave.pid \
	    --verbose

	if (( $? != 0 )); then
	    "$PGBIN"/psql -h "$MASTER_HOST" -U "$MASTER_USER" -d template1 -A -t -c 'select pg_stop_backup();'
	    echo "use omniptr make backup error in master !" \
	        | mail -s "[PostgreSQL] $(hostname) backup failed" "$ERROR_MAIL"
	    exit 1
	fi
}

# ##########################################################
# use omnipitr backup in slave
# ##########################################################
omnipitr_backup_slave() {
	local is_in_backup="$($PGBIN/psql -h $MASTER_HOST -U $MASTER_USER -d template1 -A -t -c 'select pg_is_in_backup();')"
	local today="$(date +%Y%m%d)"
	local backup_dir="$BACKUP_LOCAL/$today"

	if [[ "$is_in_backup" == "t" ]]; then
	    exit 1
	fi

	mkdir -p "$backup_dir"

	$PITR_BIN/omnipitr-backup-slave --call-master \
	    --host $MASTER_HOST \
	    --username "$MASTER_USER" \
	    --database template1 \
	    --port "$MASTER_PORT" \
	    --data-dir "$PGDATA" \
	    --source "$XLOG_ARCHIVE" \
	    --pgcontroldata-path "$PGBIN"/pg_controldata \
	    --psql-path "$PGBIN"/psql \
	    --dst-local "$backup_dir" \
	    --log "$backup_dir"/omnipitr_backup_"$today".log \
	    --pid-file "$PITR_DIR"/pitr-backup-slave.pid \
	    --verbose

	if (( $? != 0 )); then
	    "$PGBIN"/psql -h "$MASTER_HOST" -U "$MASTER_USER" -d template1 -A -t -c 'select pg_stop_backup();'
	    echo "use omnipitr make backup error in slave !" \
	        | mail -s "[PostgreSQL] $(hostname) backup failed" "$ERROR_MAIL"
	    exit 1
	fi
}

# ##########################################################
# choose omnipitr backup in master or slave
# ##########################################################
omnipitr_base_backup() {
	local is_slave="$("$PGBIN"/psql -U "$MASTER_USER" -d template1 -p "$MASTER_PORT" -A -t -c 'select pg_is_in_recovery();')"

	if ( ! type -P omnipitr-backup-master ) || [[ -d "$PITR_BIN" ]]; then
	    echo "can't find omnipitr-backup-master please check out wethere omnipitr installed in $PITR_BIN!"
	fi

	if [[ "$is_slave" == "f" ]]; then
	    omnipitr_backup_master
	else
	    omnipitr_backup_slave
	fi
}

# ##########################################################
# use pg_basebackup to backup data
# ##########################################################
pgbasebackup() {
	local today="$(date +%Y%m%d)"
	local backup_dir="$BACKUP_LOCAL/$today"

	if [[ "$is_in_backup" == "t" ]]; then
	    exit 1
	fi

	mkdir -p "$backup_dir"
	
	"$PGBIN"/pg_basebackup -h 127.0.0.1 -U "$MASTER_USER" -p "$MASTER_PORT" -x -F p -P -D "$backup_dir" &> "$backup_dir"/../pg_basebackup_"$today".log 
	
	if (( $? != 0 )); then
	    "$PGBIN"/psql -h "$MASTER_HOST" -U "$MASTER_USER" -d template1 -A -t -c 'select pg_stop_backup();'
	    echo "use pg_basebackup make backup error !" \
	        | mail -s "[PostgreSQL] $(hostname) backup failed" "$ERROR_MAIL"
	    exit 1
	fi
}

# ##########################################################
# send backup file to remote server
# ##########################################################
send_to_remote() {
	local today="$(date +%Y%m%d)"
	local backup_dir="$BACKUP_LOCAL/$today"
	local remote_dir="$BACKUP_REMOTE"

	cd $BACKUP_LOCAL
	if [[ -d "$today" ]]; then
		tar zcf "$today".tar.gz $today
	fi
	if ( ! cp -r "$backup_dir".tar.gz "$remote_dir" ); then
	    echo "send backup to remote server error" \
	        | mail -s "[PostgreSQL] $(hostname) backup failed" "$ERROR_MAIL"
	    exit 1
	else
	    rm -f "$backup_dir".tar.gz
	fi
}

# ##########################################################
# clean old backup in local server
# args:
#    arg 1: the days will keep archive
#    arg 2: the path of backup local
# ##########################################################
clean_old() {
	if (( "$#" == 2 )); then
	    local keepdays="$1"; shift
	    local backup_path="$1"; shift
	    local today="$(date +%Y%m%d)"
	    local rm_day="$(date -d "$today - $keepdays days" "+%Y%m%d")"

	    if [[ -n "$rm_day" ]] && (( "$keepdays" > 0 )); then
	        echo -e "\e[1;32m rm backup of $rm_day start:\e[0m\n"
	        touch -d "$rm_day" "$backup_path"/rm_label
	        find "$backup_path"/* -maxdepth 0 ! -newer "$backup_path"/rm_label \
	            | xargs -I {} rm -fr {}
	        echo -e "\e[1;32m rm backup of $backup_path/$rm_day done!\e[0m\n"
	    fi
	fi
}

main() {
	local keepdays=''
	local backup_tool=''
	local backup_mode=''

	while (( "$#" > 0 )); do
	    case "$1" in
	        -t|--backup-tool=*)
	            if [[ "$1" == "-t" ]]; then
	                shift
	            fi
	            backup_tool="${1##*=}"
	            shift
	        ;;
		-m|--backup-mode=*)
	            if [[ "$1" == "-m" ]]; then
	                shift
	            fi
	            backup_mode="${1##*=}"
	            shift
	        ;;
	        -k|--keep-days=*)
	            if [[ "$1" == "-k" ]]; then
	                shift
	            fi
	            keepdays="${1##*=}"
	            shift
	        ;;
	        -h|--help)
	            usage
	            exit
	        ;;
	        *)
	            break
	        ;;
	    esac
	done

	if [[ -z "$backup_mode" ]] || [[ "$backup_mode" == "auto" ]]; then
	    is_backup_server
	elif [[ "$backup_mode" == "local" ]]; then
	    :;
	fi

	if [[ -z "$backup_tool" ]] || [[ "$backup_tool" == "pg_basebackup" ]]; then
	    pgbasebackup
	elif [[ "$backup_tool" == "omnipitr" ]]; then
	    omnipitr_base_backup
	else
	    echo "don't suport backup tool $backup_tool now."
	fi

	if [[ -z "$keepdays" ]]; then
	    keepdays=-1
	fi

	send_to_remote
	clean_old "$keepdays" "$BACKUP_LOCAL"
}

main "$@"
