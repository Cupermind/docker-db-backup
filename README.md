# Introduction

This script primary purpose is to make database backups. Supported
databases:

  - MongoDB
  - MariaDB (mysql)
  - PostgreSQL

/(for supported versions list please refer to ./build.sh)/

This script supports 2 modes:

  - Standalone - for standalone severs or VMs
  - Openshift - for running in Openshift or Kubernetes contexts

# Variables

Variables list can be found in .env-example file. This file also
contains documentation and usage
scenarios.

# How to use with Openshift

``` example
oc create -f https://raw.githubusercontent.com/Cupermind/docker-db-backup/master/template.yml=
```

# Standalone use

For standalone you need to setup .env:

``` example
cp .env-example .env
```

# Development

## Testing

1.  For quickier development look into ./build.sh and comment docker
    push "$PROJECT:$TAG" so your images will be built local only.

2.  Create local .env file and then run:

    ``` example
    ./test.sh
    ```

    … which will execute docker-compose and run the script in a
    container
