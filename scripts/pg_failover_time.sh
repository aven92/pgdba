## PostgreSQL故障时间脚本

#!/bin/env bash

declare -x fail_time=0
export PGPASSWORD=''

while true; do 
    if psql -h server_ip -U postgres -Atqc 'select 1;' &>/dev/null; then
        if (( $fail_time > 0  )); then
            echo 故障恢复时间:$(date +'%F %T')
            exit
        fi
    else
        if (( $fail_time == 0  )); then
            echo 故障开始时间:$(date +'%F %T')
        fi
            fail_time+=1
    fi 
done
