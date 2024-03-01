CREATE TABLE accounts (
    account_id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);

INSERT INTO accounts VALUES
    (1, 'Alice'),
    (2, 'Bob'),
    (3, 'Charlie'),
    (4, 'David'),
    (5, 'Eve');

CREATE TABLE transactions (
    transaction_id INTEGER PRIMARY KEY,
    debit_account_id INTEGER REFERENCES accounts(account_id),
    credit_account_id INTEGER REFERENCES accounts(account_id),
    amount NUMERIC(10,2) CHECK (amount > 0)
);

INSERT INTO transactions VALUES
    (1, 1, 2, 50.00),
    (2, 2, 1, 15.50),
    (3, 2, 1, 12.15),
    (4, 1, 3, 20.00),
    (5, 3, 5, 12.34),
    (6, 3, 2, 43.21),
    (7, 5, 1, 11.11),
    (8, 1, 3, 22.11);

