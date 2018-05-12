VENV=".docker_env"

if [ ! -e "$VENV" ]; then
    virtualenv $VENV
    source $VENV/bin/activate
    pip install docker-compose==1.17.1
    if [ $? -ne 0 ]; then
        rm -rf $VENV
        exit 1
    fi
fi

source_it() {
  while read -r line; do
    if [[ -n "$line" ]] && [[ $line != \#* ]]; then
      export "$line"
    fi
  done < $1
}

source_it ".env"

source $VENV/bin/activate

docker-compose up
