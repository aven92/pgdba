#/bin/env bash

# ########################################################################
# PostgreSQL environment initialize program
# License: DBA
# Version: 1.0
# Authors: aven92
# ########################################################################

declare -r PROGDIR="$(cd $(dirname $(readlink -f $0)) && pwd)"
declare -r PROGNAME="$(basename $(readlink -f $0))"

declare -x -r DIR_BASE='/data'
declare -x -r HOME='/home'

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH

# ##########################################################
# usage of this script
# ##########################################################
usage() {
	cat <<- EOF

	usage: $PROGNAME opstions

	You must execute this program with system superuser privilege (root)!
	The product and dbversion must use together.

	OPTIONS:
	    -U, --superuser=username    Database superuser
	    -P, --product=product       product name
	    -I, --initdb                initdb or not
	    -V, --dbversion             Database version
	    -h, --help                  usage of this program

	Example:
	    $PROGNAME -P test -V 9.5.2
	    $PROGNAME -U dbsu -P test -I -V 9.5.2

	EOF
}

# ##########################################################
# check execute user
# ##########################################################
check_exec_user() {
	if [[ "$(whoami)" != "root" ]]; then
		usage
		exit -1
	fi
}

# ##########################################################
# initialize superuser
# args:
#    arg 1: superuser name
# ##########################################################
user_init() {
	if (( "$#" == 1 )); then
		local dbsu="$1"; shift

		if ( ! grep "$dbsu" /etc/group &>/dev/null ); then
		    groupadd "$dbsu"
		fi

		if ( ! id "$dbsu" &>/dev/null ); then
		    useradd -d "$HOME"/"$dbsu" -g "$dbsu" "$dbsu"
		fi

		if ( id "$dbsu" &>/dev/null ) && ( ! grep -q "$dbsu" /etc/sudoers ); then
		    chmod u+w /etc/sudoers
		    echo "$dbsu          ALL=(ALL)         NOPASSWD: ALL" >> /etc/sudoers
		fi

		return 0
	else
		return 1
	fi
}

# ##########################################################
# initialize directory
# args:
#    arg 1: superuser name
#    arg 2: databse base directory
# ##########################################################
dir_init() {
	if (( "$#" == 2 )); then
		local dbsu="$1"; shift
		local datadir="$1"; shift

		mkdir -p "$datadir"/{data,backup,rbackup,arclog,tablespace,log,conf,scripts}
		chown -R "$dbsu":"$dbsu" "$datadir"
		chmod 0700 "$datadir"/data

		return 0
	else
		return 1
	fi
}

# ##########################################################
# install package of postgresql
# args:
#    arg 1: postgresql version
# ##########################################################
pg_install() {
	if (( "$#" == 1 )); then
		local dbversion="$1"; shift
		local major_version="${dbversion:0:3}"
		local short_version="$(echo $dbversion \
		     | awk -F'.' '{print $1$2}')"
		local rpm_base=''
		local os_release=''

		if ( grep -q 'CentOS release 6' /etc/redhat-release ); then
		    rpm_base="http://yum.postgresql.org/$major_version/redhat/rhel-6Server-$(uname -m)"
		    os_release="rhel6"
		elif ( grep -q 'CentOS Linux release 7' /etc/redhat-release ); then
		    rpm_base="http://yum.postgresql.org/$major_version/redhat/rhel-7Server-$(uname -m)"
		    os_release="rhel7"
		fi

		yum install -y tcl perl-ExtUtils-Embed libxml2 libxslt uuid readline

		if ( ! rpm -q postgresql"$short_version"-libs-"$dbversion"-1PGDG."$os_release"."$(uname -m)" &> /dev/null ); then
		    rpm -ivh "$rpm_base"/postgresql"$short_version"-libs-"$dbversion"-1PGDG."$os_release"."$(uname -m)".rpm
		fi
		if ( ! rpm -q postgresql"$short_version"-"$dbversion"-1PGDG."$os_release"."$(uname -m)" &> /dev/null ); then
		    rpm -ivh "$rpm_base"/postgresql"$short_version"-"$dbversion"-1PGDG."$os_release"."$(uname -m)".rpm
		fi
		if ( ! rpm -q postgresql"$short_version"-server-"$dbversion"-1PGDG."$os_release"."$(uname -m)" &> /dev/null ); then
		    rpm -ivh "$rpm_base"/postgresql"$short_version"-server-"$dbversion"-1PGDG."$os_release"."$(uname -m)".rpm
		fi
		if ( ! rpm -q postgresql"$short_version"-contrib-"$dbversion"-1PGDG."$os_release"."$(uname -m)" &> /dev/null ); then
		    rpm -ivh "$rpm_base"/postgresql"$short_version"-contrib-"$dbversion"-1PGDG."$os_release"."$(uname -m)".rpm
		fi

		rm -f /usr/pgsql
		ln -sf /usr/pgsql-"$major_version" /opt/pgsql
		echo 'export PATH=/usr/pgsql/bin:$PATH' > /etc/profile.d/pgsql.sh
	fi
}

# ##########################################################
# install package of postgresql for zhaopin
# args:
#    arg 1: postgresql version
# ##########################################################
pg_install_zhaopin() {
	if (( "$#" == 1 )); then
		local dbversion="$1"; shift
		local major_version="${dbversion:0:3}"
		local short_version="$(echo $dbversion \
		     | awk -F'.' '{print $1$2}')"
		local rpm_base='http://download.zpidc.com/packages/RPMS/'
		local os_release=''

		if ( grep -q 'CentOS release 6' /etc/redhat-release ); then
		    os_release="el6"
		elif ( grep -q 'CentOS Linux release 7' /etc/redhat-release ); then
		    os_release="el7"
		fi

		if ( ! rpm -q postgresql-"$dbversion"-1."$os_release"."$(uname -m)" &> /dev/null ); then
		    yum install -y tcl perl-ExtUtils-Embed libxml2 libxslt uuid readline
		    rpm -ivh --force "$rpm_base"/"$(uname -m)"/postgresql-"$dbversion"-1."$os_release"."$(uname -m)".rpm
		fi
	fi
}

# ##########################################################
# postgresql optimize
# args:
#    arg 1: postgresql base directory
# ##########################################################
optimize_kernel() {
	if (( "$#" == 1 )); then
		local datadir="$1"; shift
		local mem="$(free \
		     | awk '/Mem:/{print $2}')"
		local swap="$(free \
		     | awk '/Swap:/{print $2}')"

		cat > "$datadir"/conf/sysctl.conf <<- EOF
		# Database kernel optimization
		vm.swappiness = 0
		vm.overcommit_memory = 2
		vm.overcommit_ratio = $(( ( $mem - $swap ) * 100 / $mem ))
		vm.zone_reclaim_mode = 0
		#vm.dirty_background_ratio = 10
		#vm.dirty_ratio = 20
		EOF
	fi
}

# ##########################################################
# postgresql config file
# args:
#    arg 1: postgresql superuser
#    arg 2: postgresql base directory
#    arg 3: postgresql short version
# ##########################################################
pg_conf_init() {
	if (( "$#" == 3 )); then
		local dbsu="$1"; shift
		local datadir="$1"; shift
		local short_version="$1"; shift

		wget -q -c http://172.30.200.20/conf/postgresql/pg"$short_version".conf -O "$datadir"/conf/postgresql.conf

		cat > "$datadir"/conf/pg_hba.conf <<- EOF
		host     all               $dbsu		0.0.0.0/0       reject
		host     sqldba            monitor		0.0.0.0/0	reject
		local    all               all					md5
		host     replication       all			0.0.0.0/0       md5
		host     all               all			0.0.0.0/0       md5
		EOF

		cat > "$datadir"/conf/recovery.conf <<- EOF
		standby_mode = 'on'
		primary_conninfo = 'host=localhost port=5432 user=postgres password=password application_name=$(hostname)'
		###restore_command = '/bin/cp -n $datadir/arclog/%f %p'
		###restore_command = '/usr/bin/test -f $datadir/arclog/\$(date +%Y%m%d)/%f.zip && unzip -o $datadir/arclog/\$(date +%Y%m%d)/%f.zip'
		recovery_target_timeline = 'latest'
		EOF

		chown -R "$dbsu":"$dbsu" "$datadir"
	fi
}

# ##########################################################
# postgresql initdb
# args:
#    arg 1: postgresql base directory
#    arg 2: postgresql superuser
# ##########################################################
pg_initdb() {
	if (( "$#" == 2 )); then
		local datadir="$1"; shift
		local dbsu="$1"; shift

		chown -R "$dbsu":"$dbsu" "$datadir"
		chmod 0700 "$dbsu":"$dbsu" "$datadir"/data
		su - "$dbsu" sh -c "/opt/pgsql/bin/initdb -D $datadir/data"
		su - "$dbsu" sh -c "/bin/cp -a $datadir/data/postgresql.conf $datadir/data/postgresql.conf.bak"
		su - "$dbsu" sh -c "/bin/cp -a $datadir/conf/postgresql.conf $datadir/data/postgresql.conf"
		su - "$dbsu" sh -c "/bin/cp -a $datadir/data/pg_hba.conf $datadir/data/pg_hba.conf.bak"
		su - "$dbsu" sh -c "/bin/cp -a $datadir/conf/pg_hba.conf $datadir/data/pg_hba.conf"
		su - "$dbsu" sh -c "/bin/ln -sf $datadir/log $datadir/data/pg_log"
	fi
}

main() {
	local product_name='test'
	local dbtype='postgresql'
	local db_version='9.5.2'
	local major_version='9.5'
	local short_version='95'
	local superuser='postgres'
	local dbbase="$DIR_BASE/$dbtype/${product_name}_${major_version}"
	local initflag="0"

	check_exec_user

	while (( "$#" >= 0 )); do
		case "$1" in
		    -U|--superuser=*)
		        if [[ "$1" == "-U" ]]; then
		            shift
		        fi
		        superuser="${1##*=}"
		        shift
		    ;;
		    -P|--product=*)
		        if [[ "$1" == "-P" ]]; then
		            shift
		        fi
		        product_name="${1##*=}"
		        shift
		    ;;
		    -I|--initdb)
		        initflag="1"
		        shift
		    ;;
		    -V|--dbversion=*)
		        if [[ "$1" == "-V" ]]; then
		            shift
		        fi
		        db_version="${1##*=}"
		        major_version="${db_version:0:3}"
		        short_version="$(echo $db_version | awk -F'.' '{print $1$2}')"
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

	dbtype="postgresql"
	
	if [[ "$product_name" != "" ]] && [[ "$short_version" != "" ]]; then
		dbbase="$DIR_BASE/$dbtype/${product_name}_${short_version}"
	else
		dbbase="$DIR_BASE/$dbtype"
	fi

	user_init "$superuser"
	dir_init "$superuser" "$dbbase"

	pg_install_zhaopin "$db_version"
	pg_conf_init "$superuser" "$dbbase" "$short_version"

	if (( "$initflag" == "1" )); then
	    pg_initdb "$dbbase" "$superuser"
	fi

	optimize_kernel "$dbbase"
}

main "$@"
