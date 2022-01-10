# frozen_string_literal: true

module PendingTransactionEngine
  module CanonicalPendingTransactionService
    module ImportSingle
      class Stripe
        def initialize(raw_pending_stripe_transaction:)
          @raw_pending_stripe_transaction = raw_pending_stripe_transaction
        end

        def run
          return existing_canonical_pending_transaction if existing_canonical_pending_transaction

          ActiveRecord::Base.transaction do
            attrs = {
              date: @raw_pending_stripe_transaction.date,
              memo: @raw_pending_stripe_transaction.memo,
              amount_cents: @raw_pending_stripe_transaction.amount_cents,
              raw_pending_stripe_transaction_id: @raw_pending_stripe_transaction.id
            }
            ::CanonicalPendingTransaction.create!(attrs)
          end
        end

        private

        def existing_canonical_pending_transaction
          @existing_canonical_pending_transaction ||= ::CanonicalPendingTransaction.where(raw_pending_stripe_transaction_id: @raw_pending_stripe_transaction.id).first
        end

      end
    end
  end
end
