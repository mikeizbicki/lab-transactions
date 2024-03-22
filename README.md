# Lab: Transactions

In the [consistency lab](https://github.com/mikeizbicki/lab-consistency), you created a simple database for a double-entry accounting system.
In this lab, we will extend this database to have a simple python library interface.
You will see that:

1. Database code that looks "obviously correct" can be horribly flawed.
2. How to fix these flaws using locks.
3. The performance implications of locks.

## Project Setup

Clone this repo onto the lambda server.
There is no need to fork the repository.

### Bringing up the Database

We will use postgres as our database for this lab.
Try to bring up the database with the command
```
$ docker-compose up -d
```
You should get an error about a bad port number.

In previous projects, this never happened because the database port was never exposed to the lamdba server.
In this project, however, we will will be running python code on the lambda server (and not the `pg` container) that needs to connect to the database,
and so we need to expose the port in order to do so.

Edit the `ports` field of the `docker-compose.yml` file so that your database will be exposed on a unique port that doesn't conflict with other students.
(Your UID is a reasonable choice, and you can find it by running `id -u` in the shell.)
Then re-run
```
$ docker-compose up -d
```
and ensure that you get no errors.
Verify that you are able to successfully connect to the database using psql and the command
```
$ psql postgresql://postgres:pass@localhost:<PORT>
```
where `<PORT>` should be replaced with the port number in your `docker-compose.yml` file.
Running the command
```
postgres=# \d
```
should list a handful of tables.

> **NOTE:**
> The `psql` command above is running directly on the lambda server and not inside the container.
> Previously, we have been running inside the container using a command like
> ```
> $ docker-compose exec pg psql
> ```
> There is no meaningful difference in terms of capabilities between these two commands.
> Once you're inside `psql`, it doesn't matter how you got there, you can still run whatever sql commands you'd like.

### The Schema

The most important file in any project working with databases is the `.sql` file containing the schema (i.e. CREATE TABLE commands).
This project's schema is stored in `services/pg/sql/ledger-pg.sql`.
Let's take a look at it:
```
$ cat sql/ledger-pg.sql
CREATE TABLE accounts (
    account_id SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE transactions (
    transaction_id SERIAL PRIMARY KEY,
    debit_account_id INTEGER REFERENCES accounts(account_id),
    credit_account_id INTEGER REFERENCES accounts(account_id),
    amount NUMERIC(10,2),
    CHECK (amount > 0),
    CHECK (debit_account_id != credit_account_id)
);

CREATE TABLE balances (
    account_id INTEGER PRIMARY KEY REFERENCES accounts(account_id),
    balance NUMERIC(10,2)
);
```
The `accounts` and `transactions` tables are the same as in the previous lab.
`accounts` just stores the names of all of our accounts,
and `transactions` stores every transfer of money between two accounts.

The `balances` table is new.
Why do we have it?

Recall that in the last lab we created a VIEW called `balances` that computed the total balance in each account.
It looked like
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
It turns out that this view requires $O(n)$ time to compute,
where $n$ is the total number of transactions in our history.

> **ASIDE:**
> We will see in the comming weeks that this query is implemented using an algorithm called SEQUENTIAL SCAN.
> This algorithm is basically a for loop over the entire `transactions` table,
> and that's where the $O(n)$ runtime comes from.

For the small databases we used in the last lab,
that wasn't a problem.
But in the real world, this would be a major problem.
Real accounting systems can have trillions of transactions stored in them,
and so an $O(n)$ operation would be very slow.
We need something that will take $O(1)$ time.

The `balances` table will let us achieve this faster lookup.
The basic idea is that whenever we insert a new transaction,
we should also update the corresponding rows in `balances` to apply the appropriate debits and credits.
The next section will walk you through what this code looks like.

## Task 1: Basic Correctness

The file `Ledger/__init.py__` contains our library's python code.

Open this file in `vim`.
Read the docstrings for the `Ledger` class and the `create_account` and `transfer_funds` methods.
Ensure that you understand how these methods are supposed to work.

### Adding accounts

Let's see how to use the python code to add accounts to the database.

First, we'll verify there are no accounts in the database.
Run the following commands
```
$ psql postgresql://postgres:pass@localhost:<PORT>
postgres=# select * from accounts;
 account_id | name
------------+------
(0 rows)
```
Next, we will open python in interactive mode,
create a new `Ledger` object,
and run the `create_account` method on that object.
```
$ PYTHONPATH=.
$ python3
>>> import Ledger
>>> ledger = Ledger.Ledger('postgresql://postgres:pass@localhost:<PORT>')
>>> ledger.create_account('test')
2024-03-22 00:09:04.560 - 55670 - INSERT INTO accounts (name) VALUES (:name);
2024-03-22 00:09:04.565 - 55670 - SELECT account_id FROM accounts WHERE name=:name
2024-03-22 00:09:04.568 - 55670 - INSERT INTO balances VALUES (:account_id, 0);
```
Now reconnect to psql and verify that an account has been created.
```
$ psql postgresql://postgres:pass@localhost:<PORT>
postgres=# select * from accounts;
 account_id | name
------------+------
          1 | test
(1 row)
```

### Resetting the database


## Task 1: Correctness

Open the file `Ledger/__init__.py`.
Notice that the `transfer_funds` method inside the `Ledger` class is incomplete.

### The Solution

Implement the `transfer_funds` function.


## Task 2: Correctness (When Processes Fail)

[Chaos monkey](https://netflix.github.io/chaosmonkey/) is a famous netflix tool for testing robust systems.

<img src=img/chaosmonkey.png />

Chaos monkey works by randomly killing running processes,
and then checking to see if there was any data corruption.
We will will use our own "mini chaos monkey" in this lab to test the robustness of the code you wrote for the previous task.

### The Problem

Run the command
```
$ scripts/chaosmonkey_sequential.sh
```
This file runs the `scripts/random_transactions.py` file in a loop,
but kills each process after only 1 second.

Now check to see if your code passes the consistency check
```
$ psql postgresql://postgres:pass@localhost:9999 <<< 'select sum(balance) from balances'
```
You should get that the sum is non-zero.

This is because your `transfer_funds` method is not atomic.
If the `kill` command happens anywhere inside the function,
then only some of the UPDATE/INSERT commands will take effect and not others.

### The Solution

To make your code atomic, you need to wrap it in a transaction.
Using the SQLAlchemy library, we don't directly call the `BEGIN` and `COMMIT` SQL commands.
Instead, we use the `connection.begin()` method to create a transaction.
This is commonly done inside of a `with` block so that the transaction is automatically committed when the block closes.
That is, the code looks something like
```
with self.connection.begin():
    # insert SQL commands here
```

Your next task is to make the `transfer_funds` method atomic by putting it inside a transaction.
The provided `create_account` method is atomic, and you can reference this function as an example.

Once you've made the necessary changes,
verify they work by rerunning the `chaosmonkey_sequential.sh` script and then verifying the integrity check.
Recall that you'll need to bring the database down and back up in order to reset the database between tests.

## Task 3: Correctness (With Concurrency)

Transactions prevent certain types of data corruption, but not all types of data corruption.
In this section, we will introduce a parallel version of the chaos monkey script.
We'll see that your corrected code you wrote above will still corrupt the database when run concurrently,
and we'll introduce a lock to fix the problem.

### The Problem

Run the command
```
$ scripts/chaosmonkey_parallel.sh
```
Now check to see if your code passes the consistency check
```
$ psql postgresql://postgres:pass@localhost:9999 <<< 'select sum(balance) from balances'
```
You should get that the sum is non-zero.

This is because multiple transactions are all editing the `balances` table at the same time.

### The Solution

At the top of your `transfer_funds` method,
add a SQL command that locks the `balances` table in ACCESS EXCLUSIVE MODE.
This will ensure that only one process is able to write to the table at a time, preventing the problem above.

Once you've made the necessary changes,
verify they work by rerunning the `chaosmonkey_parallel.sh` script and then verifying the integrity check.

## Task 4: The Deadlock

When you run the `chaosmonkey_parallel.sh` script, you should notice a large number of deadlock errors being reported.
You will need to fix these errors by wrapping the function in a try/except block,
and repeating the failed function call whenever

## Task 4: Speed

Finally, our code is correct!
But unfortunately, it's really slow.
The ACCESS TABLE EXCLUSIVE lock ensures that only one process can access the `balances` table at a time,
and this defeats the whole point of parallelism!

## Submission

Upload your corrected

