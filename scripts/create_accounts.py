import Ledger
import argparse

if __name__ == '__main__':

    # process command line args
    parser = argparse.ArgumentParser()
    parser.add_argument('db')
    parser.add_argument('--num_accounts', type=int, default=100)
    args = parser.parse_args()

    # generate accounts
    Ledger = Ledger.Ledger(args.db)
    for i in range(args.num_accounts):
        Ledger.create_account(f'test_account_{i:04}')

