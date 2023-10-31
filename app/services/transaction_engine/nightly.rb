# frozen_string_literal: true

module TransactionEngine
  class Nightly
    include ::TransactionEngine::Shared

    def initialize(start_date: nil)
      @start_date = start_date || last_1_month
    end

    def run
      # 1 raw imports
      import_raw_plaid_transactions!
      import_other_raw_plaid_transactions!
      # import_raw_emburse_transactions! TODO: remove completely
      import_raw_stripe_transactions!
      import_raw_csv_transactions!
      import_raw_increase_transactions!

      # 2 hashed
      hash_raw_plaid_transactions!
      # hash_raw_emburse_transactions! TODO: remove completely
      hash_raw_stripe_transactions!
      hash_raw_csv_transactions!
      hash_raw_increase_transactions!

      # 3 canonical
      canonize_hashed_transactions!

      # 4 plaid mistakes
      fix_plaid_mistakes!

      # 5 fix memo mistakes
      fix_memo_mistakes!
    end

    private

    def import_raw_plaid_transactions!
      BankAccount.syncing_v2.pluck(:id).each do |bank_account_id|
        puts "raw_plaid_transactions: #{bank_account_id}"

        ::TransactionEngine::RawPlaidTransactionService::Plaid::Import.new(bank_account_id:, start_date: @start_date).run
      end
    end

    def import_other_raw_plaid_transactions!
      ::TransactionEngine::RawPlaidTransactionService::BankAccount1::Import.new(start_date: @start_date).run
      ::TransactionEngine::RawPlaidTransactionService::BankAccount9::Import.new(start_date: @start_date).run
    end

    def calculate_n_times
      (((Time.now.utc - @start_date) / 1.day).ceil / 15.0).ceil + 1 # number of 15 days periods plus add an additional day
    end

    def import_raw_emburse_transactions!
      # Check for TXs in 1 month blocks over the past n periods at increments of 15 days
      calculate_n_times.times do |n|
        from = Date.today - (n * 15).days
        to = from + 15.days

        puts "raw_emburse_transactions: #{from} - #{to}"

        begin
          ::TransactionEngine::RawEmburseTransactionService::Emburse::Import.new(start_date: from, end_date: to).run
        rescue => e
          puts e
        end
      end
    end

    def import_raw_stripe_transactions!
      ::TransactionEngine::RawStripeTransactionService::Stripe::Import.new(start_date: @start_date).run
    end

    def import_raw_csv_transactions!
      ::TransactionEngine::RawCsvTransactionService::Import.new.run
    end

    def import_raw_increase_transactions!
      ::TransactionEngine::RawIncreaseTransactionService::Increase::Import.new(start_date: @start_date).run
    end

    def hash_raw_plaid_transactions!
      ::TransactionEngine::HashedTransactionService::RawPlaidTransaction::Import.new(start_date: @start_date).run
    end

    def hash_raw_emburse_transactions!
      ::TransactionEngine::HashedTransactionService::RawEmburseTransaction::Import.new(start_date: @start_date).run
    end

    def hash_raw_stripe_transactions!
      ::TransactionEngine::HashedTransactionService::RawStripeTransaction::Import.new(start_date: @start_date).run
    end

    def hash_raw_csv_transactions!
      ::TransactionEngine::HashedTransactionService::RawCsvTransaction::Import.new.run
    end

    def hash_raw_increase_transactions!
      ::TransactionEngine::HashedTransactionService::RawIncreaseTransaction::Import.new(start_date: @start_date).run
    end

    def canonize_hashed_transactions!
      ::TransactionEngine::CanonicalTransactionService::Import::All.new.run
    end

    def fix_plaid_mistakes!
      BankAccount.syncing_v2.pluck(:id).each do |bank_account_id|
        ::TransactionEngine::FixMistakes::Plaid.new(bank_account_id:, start_date: @start_date.to_date.iso8601, end_date: nil).run
      end
    end

    def fix_memo_mistakes!
      ::TransactionEngine::FixMistakes::Memos.new(start_date: @start_date).run
    end

  end
end
