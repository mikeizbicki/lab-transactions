FROM postgres:12

RUN apt-get update && apt-get install -y \
    less \
    make \
    vim

COPY ./sql/ledger-pg.sql /docker-entrypoint-initdb.d
