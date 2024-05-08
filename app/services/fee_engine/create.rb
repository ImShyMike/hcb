# frozen_string_literal: true

module FeeEngine
  class Create
    def initialize(canonical_event_mapping:)
      @canonical_event_mapping = canonical_event_mapping
    end

    def run
      # Require HCB Code to be present. Allows us to determine if other transactions in
      # this HCB Code had their fees waived.
      return if @canonical_event_mapping.canonical_transaction.hcb_code.nil?

      reason = determine_reason

      event_sponsorship_fee = @canonical_event_mapping.event.sponsorship_fee

      amount_cents_as_decimal = BigDecimal(@canonical_event_mapping.canonical_transaction.amount_cents.to_s) * BigDecimal(event_sponsorship_fee.to_s)
      amount_cents_as_decimal = 0 if reason != "REVENUE"

      attrs = {
        canonical_event_mapping_id: @canonical_event_mapping.id,
        reason:,
        amount_cents_as_decimal:,
        event_sponsorship_fee:
      }
      Fee.create!(attrs)
    end

    private

    def determine_reason
      canonical_transaction = @canonical_event_mapping.canonical_transaction

      reason = "TBD"

      reason = "REVENUE" if canonical_transaction.amount_cents > 0

      reason = "HACK CLUB FEE" if canonical_transaction.likely_hack_club_fee?

      reason = "REVENUE WAIVED" if canonical_transaction.likely_check_clearing_dda? # this typically has a negative balancing transaction with it
      reason = "REVENUE WAIVED" if canonical_transaction.likely_card_transaction_refund? # sometimes a user is issued a refund on a transaction
      reason = "REVENUE WAIVED" if canonical_transaction.local_hcb_code.ach_transfer? # outgoing ACH transfers are sometimes returned to the account upon failure

      # don't run fee if other transactions in it's HCB Code have fees waived
      reason = "REVENUE WAIVED" if canonical_transaction.local_hcb_code.canonical_transactions.includes(:fee).any? { |ct| ct.fee&.revenue_waived? }
      reason = "REVENUE WAIVED" if canonical_transaction.local_hcb_code.canonical_pending_transactions.any?(&:fee_waived?)

      reason = "REVENUE WAIVED" if canonical_transaction.likely_account_verification_related? # Waive fees on account verification transactions from platforms like Venmo

      reason = "DONATION REFUNDED" if canonical_transaction.local_hcb_code.donation&.refunded?

      reason
    end

  end
end
