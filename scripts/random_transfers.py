import Ledger
import random
import argparse

if __name__ == '__main__':

    # process command line args
    parser = argparse.ArgumentParser()
    parser.add_argument('--num_transfers', type=int, default=1000)
    parser.add_argument('db')
    args = parser.parse_args()

    # get account_id list
    Ledger = Ledger.Ledger(args.db)
    account_ids = Ledger.get_all_account_ids()
    if len(account_ids) == 0:
        raise ValueError('No accounts in database.  Did you run create_accounts.py?')

    # generate random transfers
    for i in range(args.num_transfers):
        debit_account_id = random.choice(account_ids)
        credit_account_id = debit_account_id
        while debit_account_id == credit_account_id:
            credit_account_id = random.choice(account_ids)
        amount = random.randint(100, 1000)
        Ledger.transfer_funds(debit_account_id, credit_account_id, amount)

