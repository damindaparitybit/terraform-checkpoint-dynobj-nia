#!/bin/bash
# v1.2 - HashiCorp Consul Integration
# This script is for Check Point Gateway
. /etc/init.d/functions
. /opt/CPshared/5.0/tmp/.CPprofile.sh

if [ ! -d "-p /usr/local/consul" ]
    then
    mkdir -p /usr/local/consul /usr/local/consul/tmp /usr/local/consul/log
    touch /usr/local/consul/current
fi

vDATE=`date +%Y-%m-%d_%H:%M:%S`
vDIR_CONSUL=/usr/local/consul
vCURRENT_GW=$vDIR_CONSUL/current_gw
vCURRENT_GW_tmp=$vDIR_CONSUL/tmp/current_gw
vCURRENT=$vDIR_CONSUL/current
vSVC_LIST=$vDIR_CONSUL/svc_list
vCONSUL_LOG=$vDIR_CONSUL/log/consul.log
vIGNORE=$vDIR_CONSUL/svc_ignore
vTMP_ADDR=$vDIR_CONSUL/tmp/tmp_addr
vTMP_CHANGES=$vDIR_CONSUL/tmp/tmp_changes
vTMP_REMOVE_SVC=$vDIR_CONSUL/tmp/tmp_remove
vTMP_SVC_KEEP=$vDIR_CONSUL/tmp/tmp_svc_keep
vSVC_NEW=$vDIR_CONSUL/tmp/tmp_svc_new
vCHANGES=$vDIR_CONSUL/changes

for file in "$vCURRENT_GW" "$vCURRENT" "$vCONSUL_LOG" "$vSVC_LIST" "$vIGNORE" "$vTMP_CHANGES" "$vSVC_NEW"
do
    if [ ! -f "$file" ]; then
    touch $file
    fi
done


f_add() {
for SVC_NAME in `cat $vCURRENT | awk -F "," '{print $1}'`
    do
    # Add new Service from Consul
    if [ `cat $vCURRENT_GW | grep -w $SVC_NAME | wc -l` == 0 ] ;
        then
            echo "dynamic_objects -n $SVC_NAME" >> $vTMP_CHANGES
            echo "$SVC_NAME" >> $vSVC_NEW
            _loop=`cat $vCURRENT | grep -w $SVC_NAME`
            for SVC_ADDR in $(echo $_loop | sed "s/,/ /g") ;
                do
                echo "dynamic_objects -o $SVC_NAME -r $SVC_ADDR $SVC_ADDR -a" >> $vTMP_ADDR
                cat $vTMP_ADDR| grep -wv "$SVC_NAME -a" >> $vTMP_CHANGES && rm $vTMP_ADDR
            done
    else
    # Add new Service Address from Consul
        _loop=`cat $vCURRENT | grep -w $SVC_NAME`
        for SVC_ADDR in $(echo $_loop | sed "s/,/ /g") ;
            do
            if [ `cat $vCURRENT_GW | grep -w $SVC_NAME | grep -w $SVC_ADDR | wc -l` == 0 ];
                then
                echo "dynamic_objects -o $SVC_NAME -r $SVC_ADDR $SVC_ADDR -a" >> $vTMP_ADDR
                cat $vTMP_ADDR | grep -wv "$SVC_NAME -a" >> $vTMP_CHANGES && rm $vTMP_ADDR
            fi
        done
    fi
done

}

f_remove() {
echo > $vTMP_REMOVE_SVC
for SVC_NAME in `cat $vCURRENT_GW | awk -F "," '{print $1}'`
    do
    # Delete Service from Consul
    if [ `cat $vCURRENT | grep -w $SVC_NAME | wc -l` == 0 ] ;
        then
            echo "dynamic_objects -do $SVC_NAME" >> $vTMP_CHANGES
            echo $SVC_NAME >> $vTMP_REMOVE_SVC
    else
    # Delete Address from Consul
        _loop=`cat $vCURRENT_GW | grep -w $SVC_NAME`
        for SVC_ADDR in $(echo $_loop | sed "s/,/ /g") ;
            do
            if [ `cat $vCURRENT | grep -w $SVC_NAME | grep -w $SVC_ADDR | wc -l` == 0 ];
                then
                echo "dynamic_objects -o $SVC_NAME -r $SVC_ADDR $SVC_ADDR -d" >> $vTMP_ADDR
                cat $vTMP_ADDR | grep -wv "$SVC_NAME -d" >> $vTMP_CHANGES && rm $vTMP_ADDR
            fi
        done
    fi
done

}

f_current_gw() {
objects=`dynamic_objects -l | grep "object name" | awk '{print $4}'`
echo > $vCURRENT_GW_tmp
for object in $objects
do
    obj_range=`dynamic_objects -lo $object| grep range | awk '{print $2}'`
    for range_number in $obj_range
        do
        start=`dynamic_objects -lo $object | grep "range $range_number" | awk '{print $4}'`
        end=`dynamic_objects -lo $object | grep "range $range_number" | awk '{print $5}'`
        if [ $start == $end ] ;
            then
            echo "$object,$start" >> $vCURRENT_GW_tmp
        else
            b=`echo $end | awk -F "." '{print $1"."$2"."$3"."$4+1}'`
            end=$b
            until [ $start = $end ]
            do
                echo "$object,$start" >> $vCURRENT_GW_tmp
                a=`echo $start | awk -F "." '{print $1"."$2"."$3"."$4+1}'`
                start=$a
            done
        fi
    done
done

svclist=`cat $vCURRENT_GW_tmp | awk -F "," '{print $1}' | sort -u`
echo > $vCURRENT_GW
for name in $svclist
do
    ip=`cat $vCURRENT_GW_tmp | grep $name | awk -F "," '{print $2}' | sort -u | awk -vORS=, '{ print $1 }' | sed 's/,$/\n/'`
    echo "$name,$ip" >> $vCURRENT_GW
done

}
f_start() {
# Extract current configuration
f_current_gw

# Loop through changes
f_add
f_remove
# Change Consul related services only
grep -w -Ff $vTMP_REMOVE_SVC $vSVC_LIST -v >> $vTMP_SVC_KEEP
cat $vTMP_SVC_KEEP | sort -u >> $vSVC_NEW
cat $vSVC_NEW | sort -u > $vSVC_LIST
grep -w -Ff $vIGNORE $vTMP_CHANGES -v > $vCHANGES
rm $vTMP_CHANGES $vTMP_REMOVE_SVC $vSVC_NEW $vTMP_SVC_KEEP

# Clean up
if [ `cat $vCHANGES | wc -l` == 0 ] ;
    then
        echo "$vDATE no changes" >> $vCONSUL_LOG
        rm $vCHANGES
    else
        sh $vCHANGES 2> /dev/null
        mv $vCHANGES $vDIR_CONSUL/log/changes.$vDATE
        echo "$vDATE updated, see changes.$vDATE for change details" >> $vCONSUL_LOG
fi
}

f_start
exit 0