#!/bin/bash

PROJECT=cupermind/db-backup
SRCS="postgres:9.4 postgres:9.5 postgres:9.6 postgres:10 postgres:11"
SRCS="$SRCS mariadb:10.3"
SRCS="$SRCS mongo:3.2 mongo:3.4 mongo:3.6"
for from in $SRCS
do
  echo $from
  TAG=${from//:/-}
  docker build --build-arg FROM=$from --tag "$PROJECT:$TAG" .
  docker push "$PROJECT:$TAG"
done
