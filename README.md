# Lab: Consistency

We say our data is *consistent* if it satisfies constraints specified in the schema.
These constraints are problem specific and ensure that we can perform meaningful analysis with the data.

In this lab, we will investigate how well SQLite, Postgres, and MySQL maintain the consistency of data.
You will see that in SQLite and MySQL it is easy to get inconsistent data,
but Postgres does a better job maintaining consistency.

For this reason, I consider Postgres to be the best choice of database for new projects.

<img src=data.png width=300px>

## Populating the Databases

Clone this repo onto the lambda server.
You do not need to fork it.

The file `ledger.sql` contains a SQL schema for a simple [double-entry bookkeeping](https://en.wikipedia.org/wiki/Double-entry_bookkeeping) system.
It contains 2 tables `accounts` and the `transactions` between those accounts.

This section will walk you through the steps of getting this schema loaded into the three different RDBMs we'll be evaluating.

### SQLite

We can use the following simple input redirection to load the `ledger.sql` file into SQLite.
```
$ sqlite3 ledger.db < ledger.sql
```

Verify that everything worked correctly by counting the number of rows in each of our tables.
```
$ sqlite3 ledger.db
sqlite> SELECT count(*) FROM accounts;
5
sqlite> SELECT count(*) FROM transactions;
8
```

### Postgres

For postgres, we first start the docker container and then use input redirection to load the schema.
```
$ docker-compose up -d --build pg
$ docker-compose exec -T pg psql < ledger.sql
CREATE TABLE
INSERT 0 5
CREATE TABLE
INSERT 0 8
```

And verify that the data was loaded into the database.
```
$ docker-compose exec pg psql
postgres=# SELECT count(*) FROM accounts;
 count
-------
     5
(1 row)

postgres=# SELECT count(*) FROM transactions;
 count
-------
     8
(1 row)

```

### MySQL

MySQL is a client/server database similar to Postgres,
and not an embedded database like sqlite.
MySQL was popular in the early 2000s due to its emphasis on speed,
but Postgres is becoming increasingly popular due to its emphasis on correctness.

> **Note:**
> The name MySQL doesn't come from the English personal pronoun "my".
> The creator of MySQL's daughter is named "My",
> and he named it after her.
> (My is a popular girl's name in Sweden.) 
> The creator also has another daughter named Maria and a son Max,
> and he has also created [MariaDB](https://mariadb.org/) and [MaxDB](https://maxdb.sap.com/) named after them.
> MariaDB fixes some structural problems with MySQL in an effort to improve consistency (although MySQL remains more popular),
> and MaxDB is the database backend of the (in)famous SAP enterprise resource management software

The `docker-compose.yml` file has an entry for both `pg` and `mysql` inside of it.
We will use docker to bring mysql up and load the data, similar to how we did with postgres.
```
$ docker-compose up -d mysql
$ docker-compose exec -T mysql mysql --protocol=TCP -Dexample -pexample < ledger.sql
```

> **Note:**
> The mysql database takes a few seconds to startup before it accepts connections.
> If you get an error running the `exec` command above that looks like
> ```
> ERROR 2003 (HY000): Can't connect to MySQL server on 'localhost:3306' (99)
> ```
> you probably just need to wait a few seconds and rerun the command.

Then we can verify that the data has been loaded into mysql with the following commands.
```
$ docker-compose exec mysql mysql --protocol=TCP -Dexample -pexample
mysql> SELECT count(*) FROM accounts;
+----------+
| count(*) |
+----------+
|        5 |
+----------+
1 row in set (0.00 sec)

mysql> SELECT count(*) FROM transactions;
+----------+
| count(*) |
+----------+
|        8 |
+----------+
1 row in set (0.01 sec)
```

Notice above that the incantation to connect to mysql is a bit more complicated than the incantation to connect to postgres.
This is because the default postgres docker images specify 

### Notice!

All three of our databases were created with the exact same SQL commands, and so we should hope that they behave exactly the same way.
It's time to find out if they do.

## A "Simple" Query

One of the things we want to do with a bookkeeping system is to check the balances of all our accounts.
We can do that with the following "simple" query:
```
SELECT
    account_id,
    name,
    coalesce(credits, 0) as credits,
    coalesce(debits, 0) as debits,
    coalesce(credits, 0) - coalesce(debits, 0) AS balance
FROM accounts
LEFT JOIN (
    SELECT credit_account_id as account_id, sum(amount) as credits
    FROM transactions
    GROUP BY credit_account_id
) AS credits USING (account_id)
FULL JOIN (
    SELECT debit_account_id as account_id, sum(amount) as debits
    FROM transactions
    GROUP BY debit_account_id
) AS debits USING (account_id)
ORDER BY account_id
;
```
Run this query in each of the databases,
and verify that the balances reported are the same.

> **Note:**
> You will get a syntax error when you run the command above on MySQL.
> MySQL does not support FULL JOINs.
> For this query, the FULL JOIN happens to be equivalent to the LEFT JOIN,
> and you can replace the FULL JOIN with the LEFT JOIN to get the query to run.

Checking the balances of our accounts is an important task,
but this query is very long and inconvenient.
So we would like a way to avoid typing it out whenever we want to check our balances.
We've seen before how to use functions in postgres to simplify writing complex queries.
Unfortunately, functions are not widely supported by other database systems.
They also turn out to be very slow for complicated reasons we're not yet ready to discuss.

In SQL, the best way to abstract away these complex queries is using a VIEW.
In sqlite, run the following command to create a VIEW of this query called `balances`.
```
CREATE VIEW balances AS
SELECT
    account_id,
    name,
    coalesce(credits, 0) as credits,
    coalesce(debits, 0) as debits,
    coalesce(credits, 0) - coalesce(debits, 0) AS balance
FROM accounts
LEFT JOIN (
    SELECT credit_account_id as account_id, sum(amount) as credits
    FROM transactions
    GROUP BY credit_account_id
) AS credits USING (account_id)
LEFT JOIN (
    SELECT debit_account_id as account_id, sum(amount) as debits
    FROM transactions
    GROUP BY debit_account_id
) AS debits USING (account_id)
ORDER BY account_id
;
```
Now you can check the balance of the users as if the results of the above query were its own table titled `balances`.
For example, you can run
```
SELECT * FROM balances;
```
or
```
SELECT balance FROM balances WHERE name='Eve';
```

### Your First Task

Modify the SQL query above so that the total number of transactions that each account has is displayed in the `balances` view.
(You will have to submit this query as part of the lab submission later.)

> **Hint:**
> You will need to use the command `DROP VIEW balances` to delete the view in order to redefine it.

> **Hint:**
> If you've re-defined the `balances` view correctly, you should get the following output.
> ```
> sqlite> select * from balances;
> | account_id |  name   | credits | debits | num transactions | balance |
> |------------|---------|---------|--------|------------------|---------|
> | 1          | Alice   | 38.76   | 92.11  | 6                | -53.35  |
> | 2          | Bob     | 93.21   | 27.65  | 4                | 65.56   |
> | 3          | Charlie | 42.11   | 55.55  | 4                | -13.44  |
> | 4          | David   | 0       | 0      | 0                | 0       |
> | 5          | Eve     | 12.34   | 11.11  | 2                | 1.23    |
> ```
<!--
CREATE VIEW balances AS
SELECT
    account_id,
    name,
    coalesce(credits, 0) as credits,
    coalesce(debits, 0) as debits,
    coalesce(credits.total, 0) + coalesce(credits.total, 0) AS "num transactions",
    coalesce(credits, 0) - coalesce(debits, 0) AS balance
FROM accounts
LEFT JOIN (
    SELECT credit_account_id as account_id, count(*) as total, sum(amount) as credits
    FROM transactions
    GROUP BY credit_account_id
) AS credits USING (account_id)
LEFT JOIN (
    SELECT debit_account_id as account_id, count(*) as total, sum(amount) as debits
    FROM transactions
    GROUP BY debit_account_id
) AS debits USING (account_id)
ORDER BY account_id
;
-->

Once you've written the code for your new `balances` VIEW,
run that code in the postgres and mysql databases as well in order to have access to the view there.

## Consistency

We say that a database is *consistent* if it satisfies certain constraints specified in the schema.
In this section, we will investigate 5 simple consistency checks in SQL and see which databases satisfy which checks.

The subsections below will give you instructions on how to fill out the following table,
which you will submit to sakai as part of your lab submission.

|                   | SQLite    | Postgres  | MySQL     |
| ----------------- | --------- | --------- | --------- |
| NUMERIC(10,2)     |           |           |           |
| NULL              |           |           |           |
| CHECK             |           |           |           |
| UNIQUE            |           |           |           |
| REFERENCES        |           |           |           |

### NUMERIC(10,2)

Notice that the `amount` column of the `transactions` table is defined to have type `NUMERIC(10,2)`:
```
CREATE TABLE transactions (
    transaction_id INTEGER PRIMARY KEY,
    debit_account_id INTEGER REFERENCES accounts(account_id),
    credit_account_id INTEGER REFERENCES accounts(account_id),
    amount NUMERIC(10,2) CHECK (amount > 0)
);

```
This is the standard type for representing money in SQL.
NUMERIC is a [fixed precision](https://en.wikipedia.org/wiki/Fixed-point_arithmetic) number representation (in this case with 10 digits before the decimal and 2 digits after).
This type is more accurate than the [IEEE754 floating point numbers](https://en.wikipedia.org/wiki/IEEE_754) used in standard programming languages like python.
The downside is that it is slower.

Out database is structured to use a double-entry bookkeeping system,
so that the sum of all balances should be 0.
That is the SQL query
```
SELECT sum(balance) FROM balances;
```
should return 0.
This will happen if the database respects the `NUMERIC` type and uses fixed point arithmetic,
but if the database does not respect this type and uses floating point values,
then we will get a non-zero number.

For each database, run the query above.
If the result is 0, enter "Yes" in the table;
otherwise enter "No".

For the small number of transactions in our table, the rounding errors will be negligible.
But real financial systems can have billions of transactions,
and small errors quickly add up.
Bitcoin exchanges, for example, are infamous for bad practices around storing money,
and [at least one exchange has lost money due to using floating point number to represnt money in their database](https://news.ycombinator.com/item?id=13784755).

<img src=penny.jpg width=400px />

### NULL

In the `accounts` table, the `name` column is defined with a `NOT NULL` constraint:
```
CREATE TABLE accounts (
    account_id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);
```
This constraint enforces that every account should have a text name.
Trying to create an account without a name should result in an error.

For each database, run the commands
```
INSERT INTO accounts VALUES (100, 'test');
INSERT INTO accounts VALUES (101, NULL);
```
If the first command succeeds and the second fails, then the database enforces the constraint and you should write "Yes" in the table.
If both commands succeed, then the database does not enforce the constraint and you should write "No" in the table.

### CHECK

The `transactions` table has `CHECK` constraint on the `amount` column:
```
CREATE TABLE transactions (
    transaction_id INTEGER PRIMARY KEY,
    debit_account_id INTEGER REFERENCES accounts(account_id),
    credit_account_id INTEGER REFERENCES accounts(account_id),
    amount NUMERIC(10,2) CHECK (amount > 0)
);
```
This constraint ensures that the amount transferred is positive.
(If the amount was 0, then no transfer occurred,
and if the amount was negative, then the debit/credit ids should be swapped.)

For each database, run the commands
```
INSERT INTO transactions VALUES (100, 1, 2, 10.0);
INSERT INTO transactions VALUES (101, 1, 2, -10.0);
```
If the first command succeeds and the second fails, then the database enforces the constraint and you should write "Yes" in the table.
If both commands succeed, then the database does not enforce the constraint and you should write "No" in the table.

### UNIQUE

The `account_id` column of the `accounts` table has a `PRIMARY KEY` constraint:
```
CREATE TABLE accounts (
    account_id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);
```
The `PRIMARY KEY` constraint is equivalent to both a `NOT NULL` constraint and a `UNIQUE` constraint.
Thus, the table definition above is equivalent to
```
CREATE TABLE accounts (
    account_id INTEGER UNIQUE NOT NULL,
    name TEXT NOT NULL
);
```
The `UNIQUE` constraint is supposed to ensure that duplicate values do not appear anywhere in the table.
In this case, we do not want two accounts with the same `account_id`,
but we do allow two accounts with the same `name`.

> **Recall:**
> We've seen from the pagila assignments that PRIMARY KEYs are common columns to use for JOINs.
> We've also seen from the quizzes that JOINs behave in unintuitive ways in the presence of NULL values or duplicate entries.
> One of the main motivations for a PRIMARY KEY constraint is to ensure simple JOIN behavior.

For each database, run the commands
```
INSERT INTO accounts VALUES (200, 'Frank');
INSERT INTO accounts VALUES (200, 'Glenda');
```
If the first command succeeds and the second fails, then the database enforces the constraint and you should write "Yes" in the table.
If both commands succeed, then the database does not enforce the constraint and you should write "No" in the table.

### REFERENCES

The `debit_account_id` and `credit_account_id` columns in the `transactions` table have a `REFERENCES` constraint:
```
CREATE TABLE transactions (
    transaction_id INTEGER PRIMARY KEY,
    debit_account_id INTEGER REFERENCES accounts(account_id),
    credit_account_id INTEGER REFERENCES accounts(account_id),
    amount NUMERIC(10,2) CHECK (amount > 0)
);
```
These constraints are designed to ensure that every transaction involves `account_id`s that actually exist in the `accounts` table.
REFERENCES constraints are more commonly called FOREIGN KEY constraints,
and there is an alternative (more verbose and complicated) SQL syntax that uses the FOREIGN KEY keywords to create the constraints.
It is common that the columns in a FOREIGN KEY constraint refer to a PRIMARY KEY in the foreign table.

For each database, run the commands
```
INSERT INTO transactions VALUES (200, 1, 2, 50.0);
INSERT INTO transactions VALUES (201, 1000, 1001, 50.0);
```
If the first command succeeds and the second fails, then the database enforces the constraint and you should write "Yes" in the table.
If both commands succeed, then the database does not enforce the constraint and you should write "No" in the table.

## Submission

Submit to sakai:

1. the SQL query you completed in Task 1 to create the modified `balances` VIEW
2. the completed table of consistency checks
