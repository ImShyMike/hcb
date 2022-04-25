# frozen_string_literal: true

module PendingTransactionEngine
  module RawPendingInvoiceTransactionService
    module Invoice
      class Import
        def initialize
        end

        def run
          pending_invoice_transactions.each do |pit|
            ::RawPendingInvoiceTransaction.find_or_initialize_by(invoice_transaction_id: pit.id.to_s).tap do |t|
              t.amount_cents = pit.amount_due
              t.date_posted = pit.created_at
            end.save!
          end

          nil
        end

        private

        def pending_invoice_transactions
          @pending_invoice_transactions ||= ::Invoice.paid_v2.not_manually_marked_as_paid.where("amount_due > 0")
        end

      end
    end
  end
end
