module CanonicalTransactionService
  class SetEvent
    def initialize(canonical_transaction_id:, event_id:)
      @canonical_transaction_id = canonical_transaction_id
      @event_id = event_id
    end

    def run
      ActiveRecord::Base.transaction do
        canonical_transaction.fees.destroy_all
        canonical_transaction.canonical_event_mapping.destroy! if canonical_transaction.canonical_event_mapping

        CanonicalEventMapping.create!(attrs) if event
      end

      canonical_transaction
    end

    private

    def event
      @event ||= ::Event.find_by(id: @event_id)
    end

    def attrs
      {
        canonical_transaction_id: canonical_transaction.id,
        event_id: @event_id
      }
    end

    def canonical_transaction
      @canonical_transaction ||= CanonicalTransaction.find(@canonical_transaction_id)
    end
  end
end
