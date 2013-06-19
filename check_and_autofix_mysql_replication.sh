#!/bin/bash

# requires mysql client, mail
# for the pingdom web check will write on /var/www/index.html 

# put in cron.d/check_and_autofix_mysql_replication something like
# */5 *     * * *     root   /usr/local/bin/check_and_autofix_mysql_replication.sh
source /etc/check_and_autofix_mysql_replication.conf
#
HOSTNAME=`hostname|cut -f1 -d '.'`
LOGFILE=/tmp/mysql_slave_checksql.log
LOGFILEDEBUG=/tmp/mysql_slave_checksql.debug.log
#

mysql -uroot -p$MYSQLPASSWD -e'show slave status \G' > $LOGFILE
SLAVESQLSTATUS=`mysql -uroot -p$MYSQLPASSWD -e'show slave status \G' |egrep -i 'Slave_SQL_Running'|awk '{print $2}'`

function innodbstatus() {

mysql -uroot -p$MYSQLPASSWD -e'SHOW ENGINE INNODB STATUS \G' > $LOGFILEDEBUG

}

function warningemail() {

innodbstatus
cat $LOGFILEDEBUG >> $LOGFILE
mail -s "Warning on $HOSTNAME: $1" $ADMINEMAIL < $LOGFILE

}

function set_pingdom_url_ok() {

cat <<EOF > /var/www/index.html
<pingdom_http_custom_check>
<status>OK</status>
<response_time>96.777</response_time>
</pingdom_http_custom_check>
EOF

}

function set_pingdom_url_err() {

cat <<EOF > /var/www/index.html
<pingdom_http_custom_check>
<status>ERROR</status>
<response_time>96.777</response_time>
</pingdom_http_custom_check>
EOF

}

function autofix() {

while true
do 
    MYSQLFIX="stop slave; set global sql_slave_skip_counter = 1;start slave;show slave status\G"
    SLAVESQLSTATUS=`mysql -uroot -p$MYSQLPASSWD -e'show slave status \G' |egrep -i 'Slave_SQL_Running'|awk '{print $2}'`
    if [ $SLAVESQLSTATUS != 'Yes' ] 
    then 
	set_pingdom_url_err
	mysql -uroot -p$MYSQLPASSWD -e$MYSQLFIX >> $LOGFILEDEBUG
	echo "skipping one record" >> $LOGFILEDEBUG 
	sleep 2
    else 
	set_pingdom_url_ok
	echo 'OK' >> $LOGFILEDEBUG
	break
    fi
done

}

if [ $SLAVESQLSTATUS != 'Yes' ] 
then 
    if
    autofix 
    then  
	warningemail 'Slave not in sync, attempting autofix'
    else
        warningemail 'Slave not in sync, errors in autofix function'
    fi
fi


