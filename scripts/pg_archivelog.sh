#!/bin/env bash

# ########################################################################
# PostgreSQL archive log program
# License: PostgreSQL DBA
# Version: 2.0
# Authors: aven
# ########################################################################

declare -r PROGDIR="$(cd $(dirname $(readlink -f $0)) && pwd)"
declare -r PROGNAME="$(basename $(readlink -f $0))"

# error mail
declare -x -r ERROR_MAIL='sqldba@zhaopin.com.cn'

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH

# ##########################################################
# usage of this script
# ##########################################################
usage() {
	cat <<- EOF

	usage: $PROGNAME [options]

	You must execute this program with the account that has privilege of pg_log directory!

	OPTIONS:
	    -d, --date=date                 date you wanna archive, default yesterday
	    -k, --keep-days=days            keep days of log archive, default keep all
	    -h, --help                      usage of this program

	Example:
	    $PROGNAME
	    $PROGNAME -d 20151117
	    $PROGNAME -k 7
	    $PROGNAME -d 20151117 -k 7

	EOF
}

# ##########################################################
# compress each postgresql log
# args:
#    arg 1: directory of pg_log
#    arg 2: the date of yesterday
#    arg 3: the mail address to send mail while execute error
# ###########################################################
compress_each_pglog() {
	if (( "$#" == 3 )); then
	    local pg_log="$1"; shift
	    local yday="$1"; shift
	    local email="$1"; shift
	
	    find $pg_log/postgresql-$yday* -name '*[csv|log]' -exec gzip -f {} \; &> /dev/null
	    if (( "$?" != "0" )); then
	        echo "gzip $(hostname)'s dblog of $yday in directory $pg_log failed" \
	            | mail -s "$(hostname):$PROGNAME failed" "$email"
	        exit 1
	    fi

	    echo -e "\e[1;32m gzip $(hostname) dblog $yday of $pg_log successed !\e[0m\n"
	    return 0
	else
	    return 1
	fi
}

# ############################################################
# archive postgresql log
# args:
#    arg 1: directory of pg_log
#    arg 2: the date of yesterday
#    arg 3: the mail address to send mail while execute error
# ############################################################
archive_pglog() {
	if (( "$#" == 3 )); then
	    local pg_log="$1"; shift
	    local yday="$1"; shift
	    local email="$1"; shift
	    local ymonth="$(date -d"$yday" +"%Y%m")"
	    local pglog_month_dir="$pg_log/$ymonth"
	    local pglog_day_dir="$pglog_month_dir/$yday"

	    [[ ! -d "$pglog_day_dir" ]] && mkdir -p "$pglog_day_dir"

	    local zip_log_file_count="$(ls $pg_log/postgresql-$yday*.gz 2>/dev/null \
	        | wc -l)"
	    echo -e "zip_log_file_count:$zip_log_file_count\n"

	    if (( "$zip_log_file_count" == "0" )); then
	        echo "can't find file postgresql-$yday*.gz in $pg_log" \
	            | mail -s "$(hostname):$PROGNAME failed" "$email"
	        exit 1
	    else
	        mv $pg_log/postgresql-$yday*.gz "$pglog_day_dir"
	        if (( "$?" != "0" )); then 
	            echo "archive dblog of $yday in directory $pg_log failed" | mail -s "$(hostname):$PROGNAME failed" "$email"
	            exit 1
	        fi
	        echo -e "archive $yday of $pg_log dblog successed !\n"
	    fi

	    return 0
	else
	    return 1
	fi
}

# ###########################################################
# compress all postgresql logs
# args:
#    arg 1: the date of yesterday
#    arg 2: the mail address to send mail while execute error
#    arg 3: history archive keep days
# ###########################################################
compress_all_pglog() {
	if (( "$#" == 3 )); then
	    local yday="$1"; shift
	    local email="$1"; shift
	    local keepdays="$1"; shift
	    local pg_processes="$(ps aux \
	        | grep -o -P 'postgres +([0-9]+).*postgres +-D +.*|postgres +([0-9]+).*postmaster +-D +.*' \
	        | grep -v 'grep')"
	    local pg_pids="$(echo $pg_processes \
	        | sed -r 's/postgres +([0-9]+).* +-D +.*/\1/g')"
	    local pg_ofs="$(echo $pg_pids \
	        | xargs -I {} lsof -p {} \
	        | grep -o -P 'postgres +[0-9]+ +postgres +cwd +DIR +.*[0-9] +(.*)$|postmaste +[0-9]+ +postgres +cwd +DIR +.*[0-9] +(.*)$' \
	        | grep -v 'grep')"
	    local pg_datas="$(echo $pg_ofs \
	        | sed -r 's/.* +([0-9])+ +postgres +cwd +DIR +.*[0-9] +(.*)$/\2/g' \
	        | sort -u)"

	    #echo -e "\e[0;33m postgres processes are:\e[0m" "$pg_processes"
	    #echo -e "\e[0;33m postgres process pids are:\e[0m" "$pg_pids"
	    #echo -e "\e[0;33m postgres process open files are:\e[0m" "$pg_ofs"
	    #echo -e "\e[0;33m postgres data directories are:\e[0m" "$pg_datas" "\n"

	    if [[ -n "$pg_datas" ]]; then
	        for pg_data in "$pg_datas"; do
	            local pg_log="$(readlink -f $pg_data/pg_log)"

	            if [[ -d "$pg_log" ]]; then
	                echo -e "\e[1;32m compress all pglogs in $pg_log start:\e[0m\n"

	                compress_each_pglog "$pg_log" "$yday" "$email"
	                archive_pglog "$pg_log" "$yday" "$email"
	                clean_old "$yday" "$keepdays" "$pg_log"

	                echo -e "\e[1;32m compress all pglogs in $pg_log done.\e[0m\n"
	            else
	                echo "can't find directory of $pg_log" \
	                    | mail -s "$(hostname):$PROGNAME failed" "$email"
	                exit 1
	            fi
	        done
	    else
	        echo -e "\e[1;31m there is no postgres server running in this $(hostname)\e[0m\n" >&2
	    fi
	    return 0
	else
	    return 1
	fi
}

# ###########################################################
# clean old archive
# args:
#    arg 1: the date of yesterday
#    arg 2: the days will keep archive
#    arg 3: the path of pglog
# ###########################################################
clean_old() {
	if (( "$#" == 3 )); then
	    local yday="$1"; shift
	    local keepdays="$1"; shift
	    local pglog_path="$1"; shift
	    local rm_month=$(date -d "$yday -$keepdays days" "+%Y%m")
	    local rm_day="$(date -d "$yday -$keepdays days" "+%Y%m%d")"

	    if [[ -n "$rm_day" ]] && (( "$keepdays" > 0 )); then
	        echo -e "\e[1;32m rm archive log of $rm_day start:\e[0m\n"
	        rm -fr "$pglog_path"/"$rm_month"/"$rm_day"
	        echo -e "\e[1;32m rm archive log of $pglog_path/$rm_month/$rm_day done!\e[0m\n"
	    fi
	fi
}

main() {
	local yday=''
	local keepdays=''

	while (( "$#" > 0 )); do
	    case "$1" in
	        -d|--date=*)
	            if [[ "$1" == "-d" ]]; then
	                shift
	            fi
	            yday="${1##*=}"
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

	if [[ -z "$yday" ]] || [[ ! "$yday" =~ ^[0-9]{8}$ ]]; then
	    yday="$(date -d'yesterday' +'%Y%m%d')"
	fi

	if [[ -z "$keepdays" ]]; then
	    keepdays=-1
	fi

	compress_all_pglog "$yday" "$ERROR_MAIL" "$keepdays"
}

main "$@"
