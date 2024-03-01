FROM mysql:8.0

#ENV MYSQL_ROOT_PASSWORD=example

#COPY my.cnf /etc/mysql

RUN echo 'CREATE DATABASE example;' >> /docker-entrypoint-initdb.d/create_db.sql
