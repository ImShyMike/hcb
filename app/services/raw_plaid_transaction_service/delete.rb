module RawPlaidTransactionService
  class Delete
    def initialize(raw_plaid_transaction_id:)
      @raw_plaid_transaction_id = raw_plaid_transaction_id
    end

    def run
      ActiveRecord::Base.transaction do
        raw_plaid_transaction.hashed_transactions.each do |ht|
          ht.canonical_transaction.fees.map(&:destroy!)
          ht.canonical_transaction.canonical_event_mapping.try(:destroy!)
          ht.canonical_transaction.canonical_hashed_mappings.map(&:destroy!)

          ht.destroy!
        end

        raw_plaid_transaction.destroy!
      end
    end

    private

    def raw_plaid_transaction
      @raw_plaid_transaction ||= ::RawPlaidTransaction.find(@raw_plaid_transaction_id)
    end
  end
end
