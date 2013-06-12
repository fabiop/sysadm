#!/bin/bash

# Check the user has aws setup

if ! [ -d ~/.ec2 ]
then 
    echo "*** This user is not configured to run ec2 commands, please config according to your distro setup ***" 
    exit 1 
fi

# Read configuration      
source /etc/aws-snap.conf

DATE=`date +%Y-%m-%d_%H-%m`

function usage() {
   echo "Usage: $0"
   echo
   echo "Create Snapshots of aws volumes"
   echo "volume list is read from config file"
   echo "volume description is created as volume name+date"   
   echo "an egrep regexp can be specified in conf file"
   echo "to exclude some hosts/volumes i.e. for test environment" 
   echo
   echo "Options: -c -m -h"
   echo "-c is mandatory to create new snapshots"   
   echo "-m is optional, sends email to admin with report"
   echo "-h or no options print this online help"
   echo
   echo "******************************************************************************"
   echo "IMPORTANT: Does not support database consistency at the moment"
   echo "TODO: ADD SUPPORT FOR DB CONSISTENCY with ec2-consistent-snapshot"
   echo "******************************************************************************"
   exit 1
}

function create_snapshots_list() {

echo "Building Volume lists from filtered snapshots -> excluding regexp $EGREPREGEXP"

export INSTANCE_LIST=`for i in \`ec2-describe-instances |grep Name|egrep -v $EGREPREGEXP|awk {'print $3'}\`; do echo "$i"; done`
echo "Instance list:"
echo $INSTANCE_LIST

echo "Volume list:"
export VOLUME_LIST=`for i in $INSTANCE_LIST; do ec2-describe-instances $i|grep BLOCKDEVICE; done |awk {'print $3'}`
echo $VOLUME_LIST

}

function do_snapshots() {

echo "------------------------------------- " >> $OUTLOG
echo " $DATE: Launching these snapshots: " >> $OUTLOG
echo "------------------------------------- " >> $OUTLOG

for i in $VOLUME_LIST
do 
    echo "-----------$i snapshot--------------- " >> $OUTLOG
    ec2-create-snapshot -d $i-$DATE $i 2>&1 >> $OUTLOG
    echo "------------------------------------- " >> $OUTLOG
done

sleep 300

echo "------------------------------------- " >> $OUTLOG
echo "Results after 5 minutes: " >> $OUTLOG
echo "------------------------------------- " >> $OUTLOG

ec2-describe-snapshots >> $OUTLOG

echo "----------------------------------------- " >> $OUTLOG
echo "END: Have a great day :)" >> $OUTLOG
echo "----------------------------------------- " >> $OUTLOG

}

#

function mail_admin()
{
    [ $EMAILADMIN ] && mail -s "Backup [ $HOSTNAME * EC2 Snapshots]" $MAILADMIN < $OUTLOG
}

[ $# -eq 0 ] && usage

while getopts mhc opt; do
   case $opt in
       c ) create_snapshots_list && do_snapshots $DESCRIPTION && mail_admin
           ;;
       m ) EMAILADMIN="TRUE"                    
           ;;
       h ) usage                       
           ;;
  esac
done

