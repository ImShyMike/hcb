# frozen_string_literal: true

module TransactionEngine
  module RawEmburseTransactionService
    module Emburse
      class Import
        include ::TransactionEngine::Shared

        def initialize(start_date: Time.now - 15.days, end_date: Time.now)
          @start_date = fmt_date start_date
          @end_date = fmt_date end_date

          @bank_account_id = "EMBURSEISSUING1"
        end

        def run
          emburse_transactions.each do |t|
            ::RawEmburseTransaction.find_or_initialize_by(emburse_transaction_id: t[:id]).tap do |et|
              et.emburse_transaction = t
              et.amount = t[:amount]
              et.date_posted = t[:time]
              et.state = t[:state]

              et.unique_bank_identifier = unique_bank_identifier
            end.save!
          end

          nil
        end

        private

        def emburse_transactions
          @emburse_transactions ||= ::Partners::Emburse::Transactions::List.new(
            start_date: @start_date,
            end_date: @end_date
          ).run
        end

        def fmt_date(date)
          unless date.methods.include? :iso8601
            raise ArgumentError.new("Only datetimes are allowed")
          end

          date = date.to_time if date.instance_of? Date
          date.iso8601
        end

      end
    end
  end
end
