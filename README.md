# Lab: Transactions

In the [consistency lab](https://github.com/mikeizbicki/lab-consistency), you created a simple database for a double-entry accounting system.
In this lab, we will extend this database to have a simple python library interface.
You will see that:

1. Database code that looks "obviously correct" can be horribly flawed.
2. How to fix these flaws using locks.
3. The performance implications of locks.

<img src=img/pitfalls1.jpg width=300px>

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
> These two commands are essentially equivalent.
> All of your SQL commands will have the exact same effects no matter how you get inside of psql.

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
we should also update the corresponding rows in the `balances` table at the same time.
That way, when we want the balance, all we need is a simple SELECT statement.

The general technique of precomputing expensive computations is called [caching](https://en.wikipedia.org/wiki/Cache_(computing)),
and it is very widely used in practice.

### Adding Accounts (I)

The file `Ledger/__init.py__` contains our library's python code.
In this section, we'll see how to use this library to manipulate the database.

<!--
Open this file in `vim`.
Read the docstrings for the `Ledger` class and the `create_account` and `transfer_funds` methods.
Ensure that you understand how these methods are supposed to work.
Let's see how to use the python code to add accounts to the database.
-->

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
$ python3
>>> import Ledger
>>> ledger = Ledger.Ledger('postgresql://postgres:pass@localhost:<PORT>')
>>> ledger.create_account('test')
2024-03-22 00:09:04.560 - 55670 - INSERT INTO accounts (name) VALUES (:name);
2024-03-22 00:09:04.565 - 55670 - SELECT account_id FROM accounts WHERE name=:name
2024-03-22 00:09:04.568 - 55670 - INSERT INTO balances VALUES (:account_id, 0);
```
The library is structured so that every time it runs a SQL command, it logs those commands to the screen for you to see.
Here, we can see that three SQL commands were run by the `create_account` method.

Now reconnect to psql and verify that an account has been created.
```
$ psql postgresql://postgres:pass@localhost:<PORT>
postgres=# select * from accounts;
 account_id | name
------------+------
          1 | test
(1 row)
```
Now reset the database by bringing it down and back up.
```
$ docker-compose down
$ docker-compose up -d
$ psql postgresql://postgres:pass@localhost:<PORT>
postgres=# select * from accounts;
 account_id | name
------------+------
(0 rows)
```

### Adding Accounts (II)

We're going to be creating some test cases soon.
To do that, we'll need an automated way of populating the database with accounts.
The file `scripts/create_accounts.py` calls the `create_account` method in a for loop to do this for us.

Run the command
```
$ python3 scripts/create_accounts.py postgresql://postgres:pass@localhost:<PORT> 
```
You probably get an error message that looks something like
```
Traceback (most recent call last):
  File "scripts/create_accounts.py", line 1, in <module>
    import Ledger
ModuleNotFoundError: No module named 'Ledger'
```
This is because when python is running a script, it defaults to assuming all `import` commands are loading installed libraries.
When we were running in interactive mode above, this was not the case, and the `import` command correctly looked in our current folder.

In order to get python to look into our current folder, we need to set the `PYTHONPATH` environment variable with the following command
```
$ export PYTHONPATH=.
```
Now, rerun the `create_accounts.py` script.
You should see a lot of output of `SELECT` and `INSERT` statements.

Connect to psql and run the command
```
SELECT count(*) FROM accounts;
```
You should see that 100 accounts have been created.

The tasks below will occasionally ask you to reset the database.
To do so, you'll need to bring it down, then back up, then recreate these accounts.

## Task 1: Correctness

We saw in the last lab that the database is able to automatically enforce certain types of correctness.
But there are other types of correctness that no database can check automatically.
In this database, one of the properties of our `balances` table is that
```
SELECT sum(balance) FROM balances;
```
should always be 0.
(Make sure you understand why before continuing.)

It is common practice to document these *invariants* that a database should maintain by writing scripts that verify the invariant.
The script `scripts/integrity_check.sh` verifies the above condition.
Run it.
```
$ sh scripts/integrity_check.sh
sum(balance) = 0.00
PASS
```
At this point, we haven't made any transactions, and so the script passes by default.

### The Problem

Run the command
```
$ python3 scripts/random_transfers.py postgresql://postgres:pass@localhost:9999
```
You should see a large number of SQL commands scroll through your screen.
The script performs 1000 random transfers between accounts by calling the `Ledger.transfer_funds` method.
(I recommend you read through the source and understand it before continuing.)

Unfortunately, the `Ledger.transfer_funds` method is currently incorrect.
Run the integrity check.
```
$ sh scripts/integrity_check.sh
```
You should see that the sum of the balances is non-zero,
and that the check fails.

### The Solution

Modify the `transfer_funds` method so that it is correct.

Run the following commands to bring the database into a sane state and test your solution
```
$ docker-compose down
$ docker-compose up -d
$ python3 scripts/create_accounts.py postgresql://postgres:pass@localhost:<PORT> 
$ python3 scripts/random_transfers.py postgresql://postgres:pass@localhost:<PORT>
$ sh scripts/integrity_check.sh
```
You won't be able to complete the next task until these checks pass.

## Task 2: Correctness (With Failing Processes)

[Chaos monkey](https://netflix.github.io/chaosmonkey/) is a famous netflix tool for testing robust systems.

<img src=img/chaosmonkey.png />

Chaos monkey works by randomly killing running processes,
and then checking to see if there was any data corruption.
We will will use our own "mini chaos monkey" in this lab to test the robustness of the code you wrote for the previous task.

### The Problem

Run the command
```
$ sh scripts/chaosmonkey_sequential.sh postgresql://postgres:pass@localhost:<PORT> 
```
This file runs the `scripts/random_transactions.py` file in a loop,
but kills each process after only 1 second.
(I recommend you read through the source and understand it before continuing.)

The database will now likely once again fail the integrity check.
```
$ sh scripts/integrity_check.sh
```
You should see that the sum of the balances is non-zero,
and that the check fails.

This is because your `transfer_funds` method is not atomic.
If the python process is killed while it is the middle of this function,
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

Run the following commands to bring the database into a sane state and test your solution.
```
$ docker-compose down
$ docker-compose up -d
$ python3 scripts/create_accounts.py postgresql://postgres:pass@localhost:<PORT> 
$ sh scripts/chaosmonkey_sequential.sh postgresql://postgres:pass@localhost:<PORT> 
$ sh scripts/integrity_check.sh
```
You won't be able to complete the next task until these checks pass.

## Task 3: Correctness (With Concurrency)

Transactions prevent certain types of data corruption, but not all types of data corruption.
In this section, we will introduce a parallel version of the chaos monkey script.
We'll see that your corrected code you wrote above will still corrupt the database when run concurrently,
and we'll need a lock to fix the problem.

### The Problem

Run the command
```
$ sh scripts/chaosmonkey_parallel.sh postgresql://postgres:pass@localhost:<PORT> 
```
This file runs many instances of the `scripts/random_transactions.py` file concurrently.
Then after waiting 10 seconds, it kills all of the running processes.
(I recommend you read through the source and understand it before continuing.)

The database will now likely once again fail the integrity check.
```
$ sh scripts/integrity_check.sh
```
This is because multiple transactions are all editing the `balances` table at the same time.
You should ensure that you understand how the SELECT and UPDATE commands can be interwoven to cause data loss before moving on.

### The Solution

At the top of your `transfer_funds` method,
add a SQL command that locks the `balances` table in ACCESS EXCLUSIVE MODE.
This will ensure that only one process is able to write to the table at a time.

Once you've made the necessary changes,
verify they work by rerunning the `chaosmonkey_parallel.sh` script and then verifying the integrity check.

> **NOTE:**
> When you run the `chaosmonkey_parallel.sh` script, you should notice a large number of deadlock errors being reported.
> You will need to fix these errors by wrapping the function in a try/except block,
> and repeating the failed `transfer_funds` function call.

## Task 4: Speed

Finally, our code is correct!
But unfortunately, it's really slow.
The ACCESS EXCLUSIVE lock ensures that only one process can access the `balances` table at a time,
and this defeats the whole point of parallelism!

Imagine if a credit card company like Visa or Mastercard implemented their accounts ledger this way with an ACCESS EXCLUSIVE lock.
Then only one person in the world would be able to use a credit card at a time.
That's obviously not a good situation to be in.
We need to find a better lock mode.

### The Solution

Currently what we're using is a table-level lock.
But this is too restrictive for our purposes.
A row-level lock would ensure that two transactions don't overwrite the balance of a single user,
while still allowing two transactions to write to two different users.

The SELECT/UPDATE pattern in the `transfer_funds` method is an extremely common pattern in database applications.
(And, as we've seen, an extremely common source of very subtle bugs!)
Postgres has implemented the FOR UPDATE clause to select statements that acquire the exact level of locking we need.

Comment out the LOCK statement that you added in the previous task,
and modify the SELECT statements to use the FOR UPDATE clause.
The FOR UPDATE clause is added to the end of SELECT statements,
so the overall commands will have the form
```
SELECT columns FROM table WHERE condition FOR UPDATE
```

Once you've made the necessary changes,
verify they work by rerunning the `chaosmonkey_parallel.sh` script and then verifying the integrity check.

### Verifying Speed Boost

Now let's verify that we are in fact inserting more transactions with the FOR UPDATE version of the code.
Run the SQL command
```
SELECT count(*) FROM transactions
```
to count the total number of transactions inserted with your improved FOR UPDATE code.
I get around 20000.

Now uncomment the LOCK command in the `transfer_funds` method.
Bring the database down, and back up, create the test accounts, and rerun the `chaosmonkey_parallel.sh` script.
Now run the SQL command
```
SELECT count(*) FROM transactions
```
and you should see that the LOCK version of the code inserts many fewer transactions than the FOR UPDATE version.
My solution only inserted about 2000 rows.

Because the LOCK version of the code is slower, comment the LOCK back out.

## Submission

Upload your completed `__init__.py` file to sakai.

