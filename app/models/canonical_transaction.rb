class CanonicalTransaction < ApplicationRecord
  include Commentable
  include Receiptable

  include PgSearch::Model
  pg_search_scope :search_memo, against: [:memo, :friendly_memo, :custom_memo, :hcb_code], using: { tsearch: { prefix: true, dictionary: "english" } }, ranked_by: "canonical_transactions.date"

  scope :unmapped, -> { includes(:canonical_event_mapping).where(canonical_event_mappings: {canonical_transaction_id: nil}) }
  scope :mapped, -> { includes(:canonical_event_mapping).where.not(canonical_event_mappings: {canonical_transaction_id: nil}) }
  scope :missing_pending, -> { includes(:canonical_pending_settled_mapping).where(canonical_pending_settled_mappings: {canonical_transaction_id: nil}) }
  scope :has_pending, -> { includes(:canonical_pending_settled_mapping).where.not(canonical_pending_settled_mappings: {canonical_transaction_id: nil}) }
  scope :missing_hcb_code, -> { where(hcb_code: nil) }
  scope :missing_or_unknown_hcb_code, -> { where("hcb_code is null or hcb_code ilike 'HCB-000%'") }
  scope :invoice_hcb_code, -> { where("hcb_code ilike 'HCB-#{::TransactionGroupingEngine::Calculate::HcbCode::INVOICE_CODE}%'") }
  scope :donation_hcb_code, -> { where("hcb_code ilike 'HCB-#{::TransactionGroupingEngine::Calculate::HcbCode::DONATION_CODE}%'") }
  scope :ach_transfer_hcb_code, -> { where("hcb_code ilike 'HCB-#{::TransactionGroupingEngine::Calculate::HcbCode::ACH_TRANSFER_CODE}%'") }
  scope :check_hcb_code, -> { where("hcb_code ilike 'HCB-#{::TransactionGroupingEngine::Calculate::HcbCode::CHECK_CODE}%'") }
  scope :disbursement_hcb_code, -> { where("hcb_code ilike 'HCB-#{::TransactionGroupingEngine::Calculate::HcbCode::DISBURSEMENT_CODE}%'") }
  scope :stripe_card_hcb_code, -> { where("hcb_code ilike 'HCB-#{::TransactionGroupingEngine::Calculate::HcbCode::STRIPE_CARD_CODE}%'") }
  scope :with_custom_memo, -> { where("custom_memo is not null") }

  scope :revenue, -> { where("amount_cents > 0") }
  scope :expense, -> { where("amount_cents < 0") }

  scope :likely_hack_club_bank_issued_cards, -> { where("memo ilike 'Hack Club Bank Issued car%'") }
  scope :likely_fee_reimbursements, -> { where("memo ilike 'FEE REFUND%FROM ACCOUNT 3302340703'") }
  scope :likely_github, -> { where("memo ilike '%github grant%'") }
  scope :likely_clearing_checks, -> { where("memo ilike '%Withdrawal - Inclearing Check #%' or memo ilike '%Withdrawal - On-Us Deposited Ite #%'") }
  scope :likely_checks, -> { where("memo ilike '%Check TO ACCOUNT 3302340703'") }
  scope :likely_achs, -> { where("memo ilike '%BUSBILLPAY%'") }
  scope :likely_donations, -> { where("memo ilike '%Hack Club Bank Donate%' or memo ilike '%HACKC DONATE%'") }
  scope :likely_hack_club_fee, -> { where("memo ilike '%Hack Club Bank Fee TO ACCOUNT%'") }
  scope :stripe_top_up, -> { where("memo ilike '%Hack Club Bank Stripe Top%' or memo ilike '%HACKC Stripe Top%'") }
  scope :not_stripe_top_up, -> { where("(memo not ilike '%Hack Club Bank Stripe Top%' and memo not ilike '%HACKC Stripe Top%') or memo is null") }
  scope :mapped_by_human, -> { includes(:canonical_event_mapping).where("canonical_event_mappings.user_id is not null").references(:canonical_event_mapping) }

  monetize :amount_cents

  has_many :canonical_hashed_mappings
  has_many :hashed_transactions, through: :canonical_hashed_mappings
  has_one :canonical_event_mapping
  has_one :event, through: :canonical_event_mapping
  has_one :canonical_pending_settled_mapping
  has_one :canonical_pending_transaction, through: :canonical_pending_settled_mapping
  has_many :fees, through: :canonical_event_mapping

  validates :friendly_memo, presence: true, allow_nil: true
  validates :custom_memo, presence: true, allow_nil: true

  after_create_commit :write_system_event

  def smart_memo
    custom_memo || less_smart_memo
  end

  def less_smart_memo
    friendly_memo || friendly_memo_in_memory_backup
  end

  def likely_disbursement?
    memo.to_s.upcase.include?("HCB DISBURSE")
  end

  def likely_hack_club_fee?
    memo.to_s.upcase.include?("HACK CLUB BANK FEE TO ACCOUNT")
  end

  def likely_check_clearing_dda?
    memo.to_s.upcase.include?("FROM DDA#80007609524 ON")
  end

  def likely_card_transaction_refund?
    likely_stripe_card_transaction? && amount_cents > 0
  end

  def likely_stripe_card_transaction?
    hashed_transactions.first.raw_stripe_transaction_id.present?
  end

  def linked_object
    @linked_object ||= TransactionEngine::SyntaxSugarService::LinkedObject.new(canonical_transaction: self).run
  end

  def deprecated_linked_object
    @deprecated_linked_object ||= begin
      obj = nil

      if raw_plaid_transaction
        ts = Transaction.with_deleted.where(plaid_id: raw_plaid_transaction.plaid_transaction_id)

        Airbrake.notify("There was more (or less) than 1 transaction for raw_plaid_transaction: #{raw_plaid_transaction.id}") unless ts.count == 1

        obj = ts.first
      end

      if raw_emburse_transaction
        ets = EmburseTransaction.with_deleted.where(emburse_id: raw_emburse_transaction.emburse_transaction_id)

        Airbrake.notify("There was more (or less) than 1 emburse_transaction for raw_emburse_transaction: #{raw_emburse_transaction.id}") unless ets.count == 1

        obj = ets.first
      end

      if raw_stripe_transaction
        sas = StripeAuthorization.where(stripe_id: raw_stripe_transaction.stripe_transaction.dig("authorization"))

        Airbrake.notify("There was more (or less) than 1 stripe_authorization for raw_stripe_transaction: #{raw_stripe_transaction.id}") unless sas.count == 1

        obj = sas.first
      end

      obj
    end
  end

  def raw_plaid_transaction
    hashed_transaction.raw_plaid_transaction
  end

  def raw_emburse_transaction
    hashed_transaction.raw_emburse_transaction
  end

  def raw_stripe_transaction
    hashed_transaction.raw_stripe_transaction
  end

  def stripe_cardholder
    @stripe_cardholder ||= begin
      return nil unless raw_stripe_transaction

      ::StripeCardholder.find_by(stripe_id: raw_stripe_transaction.stripe_transaction["cardholder"])
    end
  end

  def stripe_card
    @stripe_card ||= begin
      return nil unless raw_stripe_transaction

      ::StripeCard.find_by(stripe_id: raw_stripe_transaction.stripe_transaction["card"])
    end
  end

  def raw_pending_stripe_transaction 
    nil
  end

  def remote_stripe_iauth_id
    raw_stripe_transaction.stripe_transaction["authorization"]
  end

  def likely_waveable_for_fee?
    likely_check_clearing_dda? ||
      likely_card_transaction_refund? ||
      likely_disbursement?
  end

  # DEPRECATED
  def marked_no_or_lost_receipt_at=(v)
    v
  end

  def marked_no_or_lost_receipt_at
    nil
  end

  def display_name # in deprecated system this is the renamed transaction name
    smart_memo
  end

  def name # in deprecated system this is the imported name
    memo
  end

  def filter_data
    {} # TODO
  end

  def fee_payment?
    @fee_payment ||= fees.hack_club_fee.exists?
  end

  def invoice
    return linked_object if linked_object.is_a?(Invoice)

    nil
  end

  def invoice_payout
    return linked_object.payout if linked_object.is_a?(Invoice)

    nil
  end

  def fee_reimbursement
    nil # TODO
  end

  def check
    return linked_object if linked_object.is_a?(Check)

    nil
  end

  def ach_transfer
    return linked_object if linked_object.is_a?(AchTransfer)

    nil
  end

  def donation
    donation_payout.try(:donation)
  end

  def donation_payout
    return linked_object.payout if linked_object.is_a?(Donation)

    nil
  end

  def fee_applies?
    @fee_applies ||= fees.greater_than_0.exists?
  end

  def emburse_transfer
    nil # TODO
  end

  def disbursement
    return linked_object if linked_object.is_a?(Disbursement)

    nil
  end

  def unique_bank_identifier
    @unique_bank_identifier ||= hashed_transactions.first.unique_bank_identifier
  end

  def local_hcb_code
    @local_hcb_code ||= HcbCode.find_or_create_by(hcb_code: hcb_code)
  end

  def memo_hcb_code_likely_donation?
    memo.include?("HCB-#{::TransactionGroupingEngine::Calculate::HcbCode::DONATION_CODE}")
  end

  def memo_hcb_code_likely_invoice?
    memo.include?("HCB-#{::TransactionGroupingEngine::Calculate::HcbCode::INVOICE_CODE}")
  end

  private

  def hashed_transaction
    @hashed_transaction ||= begin
      Airbrake.notify("There was more (or less) than 1 hashed_transaction for canonical_transaction: #{canonical_transaction.id}") if hashed_transactions.count != 1

      hashed_transactions.first
    end
  end

  def friendly_memo_in_memory_backup
    @friendly_memo_in_memory_backup ||= TransactionEngine::FriendlyMemoService::Generate.new(canonical_transaction: self).run
  end

  def write_system_event
    safely do
      ::SystemEventService::Write::SettledTransactionCreated.new(canonical_transaction: self).run
    end
  end

end
