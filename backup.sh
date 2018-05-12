#!/bin/bash

DATE=`date +"%Y%m%d%H%M%S"`
DUMPNAME="${BACKUP_PREFIX}${BACKUP_TYPE}_${DB_NAME}_$DATE.gz"
S3CMD="s3cmd --access_key=${S3_ACCESS_KEY} --secret_key=${S3_SECRET_KEY} --region=${S3_REGION}"

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



s3_upload() {
  # $1 - filename
  $S3CMD put $1 s3://"$S3_BUCKET"/"$S3_DUMP_DIR/"$1
}

rotate_backups() {
  # https://serverfault.com/questions/221734/automatically-delete-old-items-from-s3-bucket/361434
  $S3CMD ls s3://"$S3_BUCKET"/"$S3_DUMP_DIR/" | \
    while read -r line;  do
      createDate=`echo $line|awk {'print $1" "$2'}`
      createDate=`date -d"$createDate" +%s`
      olderThan=`date -d"-$BACKUP_KEEP_DAYS days" +%s`
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
}

id
mkdir -p "$DUMP_DIR"
cd "$DUMP_DIR" || exit 2

if [[ -z "$GPG_KEYS" ]]; then
  GPG="cat"
else
  echo Importing GPG keys from $GPG_KEYSERVER
  DUMPNAME="$DUMPNAME.gpg"
  GPG_RECIPIENTS=""
  for key in ${GPG_KEYS//,/ }
  do
    echo Importing $key
    gpg --keyserver "$GPG_KEYSERVER" --recv-keys "$key"
    GPG_RECIPIENTS="$GPG_RECIPIENTS -r $key"
  done
  GPG="gpg -e --trust-model always $GPG_RECIPIENTS"
fi

echo Backing up  $DB_NAME from $DB_HOST to $DUMPNAME

if wait_port $DB_HOST $DB_PORT; then
  echo Port available
else
  >&2 echo "DB PORT $DB_PORT isn't available"
    /code/slack.sh OOPS "DB PORT $DB_PORT isn't available: $DUMPNAME"
  exit 1
fi

if [[ ${BACKUP_TYPE} == "postgres" ]] ; then
  export PGPASSWORD="$DB_PASS"
  if /usr/bin/pg_dump  -c -O -d "$DB_NAME" -h "$DB_HOST" -U "$DB_USER" -p "$DB_PORT" | gzip | $GPG > "$DUMPNAME" ; test ${PIPESTATUS[0]} -eq 0
  then
    echo "Dump created"
  else
    echo "DB dump failed"
    /code/slack.sh OOPS "postgres DB dump failed for: $DUMPNAME"
    exit 1
  fi
fi


if [[ ${BACKUP_TYPE} == "maria" ]] ; then
  if mysqldump -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" --port="$DB_PORT" | gzip | $GPG > "$DUMPNAME" ; test ${PIPESTATUS[0]} -eq 0
  then
    echo "Dump created"
  else
    echo "DB dump failed"
    /code/slack.sh OOPS "maria DB dump failed for: $DUMPNAME"
    exit 1
  fi
fi

if [[ ${BACKUP_TYPE} == "mongo" ]] ; then
  if mongodump --archive --host "$DB_HOST" -u "$DB_USER" -p "$DB_PASS" --db "$DB_NAME" | gzip | $GPG > "$DUMPNAME" ; test ${PIPESTATUS[0]} -eq 0
  then
    echo "Dump created"
  else
    echo "DB dump failed"
    /code/slack.sh OOPS "mongo DB dump failed for: $DUMPNAME"
    exit 1
  fi
fi

echo "Creating md5sum"
if /usr/bin/md5sum $DUMPNAME > $DUMPNAME.md5sum
then
  echo "md5sum file created"
else
  echo "md5sum failed"
  /code/slack.sh OOPS "md5sum failed for: $DUMPNAME"
  exit 1
fi

if [[ ! -z "$S3_ACCESS_KEY" ]]; then
  s3_upload $DUMPNAME
  s3_upload $DUMPNAME.md5sum
  if [[ ! -z "$BACKUP_KEEP_DAYS" ]]; then
    rotate_backups
  fi
fi

echo "Backup process completed"
#tail -f /dev/null

/code/slack.sh OK "Backup process completed, dump file: $DUMPNAME"
exit 0
