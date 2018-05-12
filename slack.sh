#!/bin/bash
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
  \"text\": \"${ICON} $2\"}" ${SLACK_WEBHOOK}
