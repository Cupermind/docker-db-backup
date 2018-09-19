#!/bin/bash

source_it() {
  while read -r line; do
    if [[ -n "$line" ]] && [[ $line != \#* ]]; then
      export "$line"
    fi
  done < $1
}

# This script can work as standalone script. Normally it reads all environment variables
# from OpenShift, but if .env is present it will override it.
if [ -f .env ]; then
  source_it ".env"
fi


DATE=`date +"%Y%m%d%H%M%S"`
DUMPNAME="${BACKUP_PREFIX}${BACKUP_TYPE}_${DB_NAME}_$DATE.gz"
S3CMD="s3cmd --access_key=${S3_ACCESS_KEY} --secret_key=${S3_SECRET_KEY} --region=${S3_REGION}"
VERSION="1.3"

# check if home directory is writable, and use /tmp if not
touch 123 2>/dev/null || export HOME=/tmp
cd $HOME

s3_upload() {
  # $1 - filename
  $S3CMD put $1 s3://"$S3_BUCKET"/"$S3_DUMP_DIR/"$1
}


wait_port() {
  #
  # $1 - host, $2 -port, $3 - wait in sec (default 60)
  #
  WAIT=${3:-60}
  for i in $(seq 1 $WAIT); do
    if nc -z $1 $2; then
      return 0
    else
      >&2 echo "Waiting for $1:$2 ($i sec)"
      sleep 1
    fi
  done
  return 1
}


receive_gpg_key() {
  #
  # $1 - key
  #
  WAIT=120
  for i in $(seq 1 $WAIT); do
    if gpg --keyserver "$GPG_KEYSERVER" --recv-keys "$key"; then
      return 0
    else
      >&2 echo "Waiting for $GPG_KEYSERVER to became available (receiving $key)"
      sleep 3
    fi
  done
  return 1
}


slack_post() {
  if [[ -z ${SLACK_WEBHOOK} ]]; then
    echo $2
    exit 0
  fi
  if [ "$1" = "OOPS" ]; then
    ICON=":exclamation:"
  elif [ "$1" = "OK" ]; then
    ICON=":white_check_mark:"
  else
    ICON=":white_medium_square:"
  fi
  #Send message to Slack
  curl -X POST -H 'Content-type: application/json' --data "{\
  \"channel\": \"${SLACK_CHANNEL}\",\
  \"username\": \"${SLACK_USERNAME}\",\
  \"text\": \"${ICON} v.${VERSION} $2\"}" ${SLACK_WEBHOOK}
}


rotate_backups() {
  # https://serverfault.com/questions/221734/automatically-delete-old-items-from-s3-bucket/361434
  if [[ ! -z "$REMOTE_BACKUP_KEEP_DAYS" ]]; then
    $S3CMD ls s3://"$S3_BUCKET"/"$S3_DUMP_DIR/" | \
      while read -r line;  do
        createDate=`echo $line|awk {'print $1" "$2'}`
        createDate=`date -d"$createDate" +%s`
        olderThan=`date -d"-$REMOTE_BACKUP_KEEP_DAYS days" +%s`
        if [[ $createDate -lt $olderThan ]]
        then
          fileName=`echo $line|awk '{$1=$2=$3=""; print $0}' | sed 's/^[ \t]*//'`
          echo $fileName
          if [[ $fileName != "" ]]
          then
            $S3CMD del "$fileName"
          fi
        fi
      done;
  fi
  if [[ ! -z "$LOCAL_BACKUP_KEEP_DAYS" ]]; then
    find . -name "${BACKUP_PREFIX}*" -ctime "+$LOCAL_BACKUP_KEEP_DAYS" -exec rm -vf \{\} \;
  fi
}


if [[ -z "$GPG_KEYS" ]]; then
  GPG="cat"
else
  echo Importing GPG keys from $GPG_KEYSERVER
  
  DUMPNAME="$DUMPNAME.gpg"
  GPG_RECIPIENTS=""
  for key in ${GPG_KEYS//,/ }
  do
    if gpg --list-keys $key 2>/dev/null; then
      echo Encryption key $key is already present
    else
      echo Receiving $key from "$GPG_KEYSERVER"
      receive_gpg_key "$key" || exit 0
    fi
    GPG_RECIPIENTS="$GPG_RECIPIENTS -r $key"
  done
  GPG="gpg -e --trust-model always $GPG_RECIPIENTS"
fi

echo Backing up  $DB_NAME from $DB_HOST to $DUMPNAME


if [[ ! -z "$DB_HOST" ]]  && [[  ! -z "$DB_PORT" ]] ; then
  if wait_port $DB_HOST $DB_PORT; then
    echo Port available
  else
    >&2 echo "DB PORT $DB_PORT isn't available"
    slack_post OOPS "DB PORT $DB_PORT isn't available: $DUMPNAME"
    exit 1
  fi
fi

if [[ ${BACKUP_TYPE} == "postgres" ]] ; then
  export PGPASSWORD="$DB_PASS"
  if /usr/bin/pg_dump  -c -O -d "$DB_NAME" -h "$DB_HOST" -U "$DB_USER" -p "$DB_PORT" | gzip | $GPG > "$DUMPNAME" ; test ${PIPESTATUS[0]} -eq 0
  then
    echo "Dump created"
  else
    echo "DB dump failed"
    slack_post OOPS "postgres DB dump failed for: $DUMPNAME"
    exit 1
  fi
fi


if [[ ${BACKUP_TYPE} == "maria" ]] ; then
  if mysqldump -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" --port="$DB_PORT" | gzip | $GPG > "$DUMPNAME" ; test ${PIPESTATUS[0]} -eq 0
  then
    echo "Dump created"
  else
    echo "DB dump failed"
    slack_post OOPS "maria DB dump failed for: $DUMPNAME"
    exit 1
  fi
fi

if [[ ${BACKUP_TYPE} == "mongo" ]] && [[ -z "$MONGO_URI" ]] ; then
  if mongodump --archive --host "$DB_HOST" -u "$DB_USER" -p "$DB_PASS" --db "$DB_NAME" | gzip | $GPG > "$DUMPNAME" ; test ${PIPESTATUS[0]} -eq 0
  then
    echo "Dump created"
  else
    echo "DB dump failed"
    slack_post OOPS "mongo DB dump failed for: $DUMPNAME"
    exit 1
  fi
fi

if [[ ${BACKUP_TYPE} == "mongo" ]] && [[ ! -z "$MONGO_URI" ]] ; then
  if mongodump --archive --uri "$MONGO_URI" | gzip | $GPG > "$DUMPNAME" ; test ${PIPESTATUS[0]} -eq 0
  then
    echo "Dump created"
  else
    echo "DB dump failed"
    slack_post OOPS "mongo DB dump failed for: $DUMPNAME"
    exit 1
  fi
fi

echo "Creating md5sum"
if /usr/bin/md5sum $DUMPNAME > $DUMPNAME.md5sum
then
  echo "md5sum file created"
  DUMPSIZE=`du -sh "$DUMPNAME" | cut -f1`
else
  echo "md5sum failed"
  slack_post OOPS "md5sum failed for: $DUMPNAME"
  exit 1
fi

if [[ ! -z "$S3_ACCESS_KEY" ]]; then
  s3_upload $DUMPNAME
  s3_upload $DUMPNAME.md5sum
  rotate_backups
fi

echo "Backup process completed"

slack_post OK "Backup process completed, dump file: $DUMPNAME size: $DUMPSIZE"
exit 0
