# https://docs.docker.com/engine/reference/builder/#understand-how-arg-and-from-interact
ARG  FROM
FROM ${FROM}

ENV DUMP_DIR /dumps
RUN apt-get update && apt-get install -y \
    gnupg \
    python-pip \
    curl \
    netcat && pip install s3cmd j2cli

RUN mkdir -p ${DUMP_DIR} && chmod 0777 ${DUMP_DIR}

WORKDIR /code

COPY backup.sh ./

CMD /code/backup.sh
