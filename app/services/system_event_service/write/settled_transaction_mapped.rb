# frozen_string_literal: true

module SystemEventService
  module Write
    class SettledTransactionMapped
      NAME = "settledTransactionMapped"

      def initialize(canonical_transaction:,
                     canonical_event_mapping:,
                     user:)
        @canonical_transaction = canonical_transaction
        @canonical_event_mapping = canonical_event_mapping
        @user = user
      end

      def run
        ::SystemEventService::Create.new(
          name:,
          properties:
        ).run
      end

      private

      def name
        NAME
      end

      def properties
        {
          canonical_transaction: {
            id: @canonical_transaction.id,
            date: @canonical_transaction.date,
            memo: @canonical_transaction.memo,
            amount_cents: @canonical_transaction.amount_cents
          },
          canonical_event_mapping: {
            id: @canonical_event_mapping.try(:id),
            canonical_transaction_id: @canonical_event_mapping.try(:canonical_transaction_id),
            event_id: @canonical_event_mapping.try(:event_id)
          },
          user: {
            id: @user.id
          }
        }
      end

    end
  end
end
