#!/bin/bash 

DATE=`date +%Y-%m-%d_%H-%m`
LOG=/tmp/aws-test-env_$DATE.log

# Source config variables
source /etc/aws-test-env.conf

# Check arguments are provided

function usage() {
   ME=`basename $0`
   echo "Manage test environments in AWS Virtual Private Cloud"
   echo "Usage: $ME [OPTION] [ARGUMENT]"
   echo "-h help"
   echo "-l list"
   echo "-n <THIRD LEVEL DOMAIN NAME> (option reqired for -c)"
   echo "-f <FRONTEND BRANCHID> (option reqired for -c)"
   echo "-b <BACKEND BRANCHID> (option reqired for -c)"
   echo "-c create (requires -n, -f, -b)" 
   echo "-r remove <BRANCHID>" 
   echo "Examples:"
   echo "List branches:     $ME -l"
   echo "Create new branch: $ME -n urlthirdlevel -f develop -b master -c"
   echo "Remove branch:     $ME -r urlthirdlevel"
   exit
}

function check_c() {

if ! $cflag 
then
    echo "-c must be included to create an instance when using -n, -f and -b." >&2
    exit 1
fi

}

function list() {

echo "================== DNS ====================="
echo "$DOMAINNAME "
cli53 export $DOMAINNAME|grep 'IN A'

echo "=========== knife client config ============" 
knife client list 
echo "=========== knife node config =============="
knife node list


if command_exists notify_skypebot
then
# notify skypebot
notify_skypebot "$THIRDLEVELDOMAINNAME.vivodot.com" || exit 0
fi

}

function exit_with_err() {

echo "$1"
exit 1

}

function databag() {

[ $THIRDLEVELDOMAINNAME ] || exit_with_err "Hostname (third level only) must be defined, exiting otherwise, sorry."
[ $FRONTEND ] || exit_with_err "Frontend version must be defined, exiting otherwise, sorry."
[ $BACKEND ] || exit_with_err "Backend version must be defined, exiting otherwise, sorry."

echo "Creating databag and uploading it into Chef server... "

[ -d $DATABAGDIR ] || mkdir -p $DATABAGDIR

cat <<EOF > $DATABAGDIR/$THIRDLEVELDOMAINNAME.json

{
"id": "$THIRDLEVELDOMAINNAME",
"thirdleveldomain": "$THIRDLEVELDOMAINNAME",
"backend_branch": "$BACKEND",
"frontend_branch": "$FRONTEND"
}
EOF

knife data bag from file gitbranches $DATABAGDIR/$THIRDLEVELDOMAINNAME.json
knife data bag show gitbranches $THIRDLEVELDOMAINNAME

}

function createbase() {

[ $THIRDLEVELDOMAINNAME ] || exit_with_err "Hostname (third level only) must be defined, exiting otherwise, sorry."

echo "Creating test env for $THIRDLEVELDOMAINNAME.$DOMAINNAME appending log in $LOG"

# Initialize ec2 instance and bootstrap Chef within it
knife ec2 server create --region eu-west-1 -s $SUBNETID -I $AMIID \
                         -N $THIRDLEVELDOMAINNAME.$DOMAINNAME -f $SIZEID \
                         -i $PEMKEY -x root \
                         -r 'role[base]' |tee $LOG

IPADDR=`cat $LOG|grep IP $LOG|uniq|awk {'print $4'}`

cli53 rrcreate vivodot.com $THIRDLEVELDOMAINNAME A $IPADDR --ttl 60
cli53 rrcreate vivodot.com mgmt.$THIRDLEVELDOMAINNAME A $IPADDR --ttl 60

knife node run_list add $THIRDLEVELDOMAINNAME.vivodot.com \'$DEFAULTROLE\'

echo "Host: run_list for $DEFAULTROLE added to $THIRDLEVELDOMAINNAME"

echo -n "Sleeping 60s to wait the dns ..."
sleep 60
echo " ok."

ssht $THIRDLEVELDOMAINNAME chef-client

if command_exists notify_skypebot
then
# notify skypebot
notify_skypebot "$THIRDLEVELDOMAINNAME.$DOMAINNAME" || exit 0
fi

}

function remove() {

[ $THIRDLEVELDOMAINNAME ] || exit_with_err "Hostname must be defined, exiting otherwise, sorry."

echo $THIRDLEVELDOMAINNAME |grep -q $DOMAINNAME && exit_with_err "Please do not put $DOMAINNAME, only third level domain"

echo -n "Are you sure you want to terminate: $THIRDLEVELDOMAINNAME $INSTANCEID? (y/n) "
read a
if [ $a = 'y' ] || [ $a = 'Y' ] 
then
    INSTANCEID=""
    INSTANCEID=`ec2-describe-instances|grep $THIRDLEVELDOMAINNAME|head -n1|awk {'print $3'}`
    if [ $INSTANCEID ]
    then
    knife ec2 server delete --region $REGION -y $INSTANCEID
    echo "Deleting DNS A Records"
    cli53 rrdelete $DOMAINNAME $THIRDLEVELDOMAINNAME
    cli53 rrdelete $DOMAINNAME mgmt.$THIRDLEVELDOMAINNAME
    echo "Deleting $THIRDLEVELDOMAINNAME data bag from Chef server"    
    knife data bag delete gitbranches -y $THIRDLEVELDOMAINNAME
    echo "Deleting $THIRDLEVELDOMAINNAME chef client"
    knife client delete -y $THIRDLEVELDOMAINNAME.$DOMAINNAME
    echo "Deleting $THIRDLEVELDOMAINNAME chef node"
    knife node delete -y $THIRDLEVELDOMAINNAME.$DOMAINNAME
    else
    echo "Instance not found."
    fi
fi

}

# Check dependencies on tools

command_exists () {
    type "$1" &> /dev/null 
}

for i in $DEPENDENCIES
  do
    command_exists $i || exit_with_err "Command -> $i <- is required, please install it."
done

[ $# -eq 0 ] && usage

while getopts hln:f:b:cr: opt; do
   case $opt in
       h ) usage
           ;;
       l ) list
           ;;
       n ) export THIRDLEVELDOMAINNAME=$OPTARG
	   ;;
       f ) export FRONTEND=$OPTARG
	   ;;
       b ) export BACKEND=$OPTARG
	   ;;       
       c ) lockfile-check $LOCKFILE && exit_with_err "Another deployment is running ... exiting." || lockfile-create $LOCKFILE
	   cflag=true
	   databag 
	   createbase $THIRDLEVELDOMAINNAME
	   lockfile-remove $LOCKFILE
           ;;
       r ) export THIRDLEVELDOMAINNAME=$OPTARG
	   remove 
           ;;
   esac
done
