#!/bin/bash -e                                                                                                       

DATE=`date +%Y-%m-%d`
S3CMD=/usr/bin/s3cmd

# S3 LOG bucket name without the s3 url
# **** CAREFUL THIS BUCKET WILL BE EMPTIED ****
S3BUCKETNAME="my.s3.log.bucket.name"
LOGDIR=/var/log/s3/${S3BUCKETNAME}

# check if s3cmd is installed and configured
${S3CMD} ls > /dev/null || (echo 's3cmd needs to be installed and configured'; exit 1)

# create todays' logdir                                                                                              
mkdir -p ${LOGDIR}/${DATE}

# download todays' files                                                                                             
if ${S3CMD} sync --recursive s3://${S3BUCKETNAME}/ ${LOGDIR}/${DATE}
then
    # cleanup todays' files in S3                                                                                    
    ${S3CMD} del s3://${S3BUCKETNAME}/*
fi

# concatenate today's files in one logfile                                                                           
> ${LOGDIR}/${DATE}.log
# a placeholder file is needed to avoid the error of catting nothing if there are no logs                            
> ${LOGDIR}/${DATE}/placeholder

if cat ${LOGDIR}/${DATE}/* >> ${LOGDIR}/${DATE}.log
then
    # remove all the local small logfiles and dir                                                                    
    rm /var/log/s3/${S3BUCKETNAME}/${DATE}/ -rf
fi

# rotate old logs                                                                                                    
[ -f ${LOGDIR}/today.log ] && mv ${LOGDIR}/today.log ${LOGDIR}/yesterday.log

# put the log where awstats is supposed to find it                                                                   
cp -av ${LOGDIR}/${DATE}.log ${LOGDIR}/today.log

# compress old logs                                                                                                  
gzip -9f ${LOGDIR}/${DATE}.log
