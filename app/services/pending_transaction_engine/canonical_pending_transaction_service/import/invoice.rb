# frozen_string_literal: true

module PendingTransactionEngine
  module CanonicalPendingTransactionService
    module Import
      class Invoice
        def run
          raw_pending_invoice_transactions_ready_for_processing.find_each(batch_size: 100) do |rpit|
            ::PendingTransactionEngine::CanonicalPendingTransactionService::ImportSingle::Invoice.new(raw_pending_invoice_transaction: rpit).run
          end
        end

        private

        def raw_pending_invoice_transactions_ready_for_processing
          @raw_pending_invoice_transactions_ready_for_processing ||= begin
            return RawPendingInvoiceTransaction.all if previously_processed_raw_pending_invoice_transactions_ids.length < 1

            RawPendingInvoiceTransaction.where("id not in(?)", previously_processed_raw_pending_invoice_transactions_ids)
          end
        end

        def previously_processed_raw_pending_invoice_transactions_ids
          @previously_processed_raw_pending_invoice_transactions_ids ||= ::CanonicalPendingTransaction.invoice.pluck(:raw_pending_invoice_transaction_id)
        end

      end
    end
  end
end
