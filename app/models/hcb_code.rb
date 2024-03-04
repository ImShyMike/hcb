# frozen_string_literal: true

# == Schema Information
#
# Table name: hcb_codes
#
#  id                           :bigint           not null, primary key
#  hcb_code                     :text             not null
#  marked_no_or_lost_receipt_at :datetime
#  short_code                   :text
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_hcb_codes_on_hcb_code  (hcb_code) UNIQUE
#
class HcbCode < ApplicationRecord
  has_paper_trail

  include PublicIdentifiable
  set_public_id_prefix :txn

  include Hashid::Rails

  include Commentable
  include Receiptable

  include Memo

  monetize :amount_cents

  has_and_belongs_to_many :tags

  has_many :suggested_pairings
  has_many :suggested_receipts, source: :receipt, through: :suggested_pairings

  has_one :personal_transaction, required: false
  has_one :pin, required: false

  before_create :generate_and_set_short_code

  delegate :likely_account_verification_related?, :fee_payment?, to: :ct, allow_nil: true

  comma do
    hcb_code "HCB Code"
    created_at "Created at"
    date "Transaction date"
    url "URL" do |url| "https://hcb.hackclub.com#{url}" end
    memo
    receipts size: "Receipt count"
    receipts "Has receipt?" do |receipts| receipts.exists? end
  end

  def url
    "/hcb/#{hashid}"
  end

  def popover_url
    "/hcb/#{hashid}?frame=true"
  end

  def receipt_upload_email
    if Rails.env.development?
      "receipts+hcb-#{hashid}@bank-parse-dev.hackclub.com"
    else
      "receipts+hcb-#{hashid}@hcb.hackclub.com"
    end
  end

  def best_suggested_receipts(limit: nil, threshold: nil, only_unreviewed: false)
    pairings = only_unreviewed ? suggested_pairings.unreviewed : suggested_pairings

    if threshold
      pairings = pairings.where("distance <= ?", threshold)
    end

    pairings.includes(:receipt).order(distance: :asc).limit(limit).map(&:receipt).compact
  end

  def date
    @date ||= ct.try(:date) || pt.try(:date)
  end

  def type
    return :unknown if unknown?
    return :invoice if invoice?
    return :donation if donation?
    return :partner_donation if partner_donation?
    return :ach if ach_transfer?
    return :check if check?
    return :disbursement if disbursement?
    return :card_charge if stripe_card?
    return :bank_fee if bank_fee?

    nil
  end

  def humanized_type
    return "ACH" if ach_transfer?
    return "Bank Fee" if bank_fee?

    t = type || :transaction
    t = :transaction if unknown?

    t.to_s.humanize
  end

  def amount_cents
    @amount_cents ||= begin
      return canonical_transactions.sum(:amount_cents) if canonical_transactions.exists?

      # ACH transfers that haven't been sent don't have any CPTs
      return ach_transfer.amount if ach_transfer?

      canonical_pending_transactions.sum(:amount_cents)
    end
  end

  def amount_cents_by_event(event)
    if canonical_transactions.exists?
      return canonical_transactions
             .includes(:canonical_event_mapping)
             .where(canonical_event_mapping: { event_id: event.id })
             .sum(:amount_cents)
    end

    # ACH transfers that haven't been sent don't have any CPTs
    return ach_transfer.amount if ach_transfer?

    canonical_pending_transactions
      .includes(:canonical_pending_event_mapping)
      .where(canonical_pending_event_mapping: { event_id: event.id })
      .sum(:amount_cents)
  end

  has_many :canonical_pending_transactions,
           foreign_key: "hcb_code",
           primary_key: "hcb_code",
           inverse_of: :local_hcb_code

  has_many :canonical_transactions,
           -> { order("canonical_transactions.date desc, canonical_transactions.id desc") },
           foreign_key: "hcb_code",
           primary_key: "hcb_code",
           inverse_of: :local_hcb_code

  def event
    events.first
  end

  def events
    @events ||=
      begin
        ids = [].concat(canonical_pending_transactions.includes(:canonical_pending_event_mapping).pluck(:event_id))
                .concat(canonical_transactions.includes(:canonical_event_mapping).pluck(:event_id))
                .compact
                .uniq

        return Event.where(id: ids) unless ids.empty?

        ids.concat([
          invoice.try(:event).try(:id),
          donation.try(:event).try(:id),
          partner_donation.try(:event).try(:id),
          ach_transfer.try(:event).try(:id),
          check.try(:event).try(:id),
          increase_check.try(:event).try(:id),
          disbursement.try(:event).try(:id),
          check_deposit.try(:event).try(:id),
          bank_fee.try(:event).try(:id),
        ].compact.uniq)

        ids << EventMappingEngine::EventIds::INCOMING_FEES if incoming_bank_fee?
        ids << EventMappingEngine::EventIds::HACK_CLUB_BANK if fee_revenue?

        Event.where(id: ids)
      end
  end

  def pretty_title(show_event_name: true, show_amount: false)
    event_preposition = [:unknown, :invoice, :ach, :check, :card_charge, :bank_fee].include?(type || :unknown) ? "in" : "to"
    amount_preposition = [:transaction, :donation, :partner_donation, :disbursement, :card_charge, :bank_fee].include?(type || :unknown) ? "of" : "for"

    amount_preposition = "refunded" if stripe_refund?

    title = [humanized_type]
    title << amount_preposition << ApplicationController.helpers.render_money(stripe_card? ? amount_cents.abs : amount_cents) if show_amount
    title << event_preposition << event.name if show_event_name

    title.join(" ")
  end

  def raw_stripe_transaction
    ct&.raw_stripe_transaction
  end

  def stripe_card
    pt.try(:stripe_card) || ct.try(:stripe_card)
  end

  def stripe_cardholder
    pt.try(:stripe_cardholder) || ct.try(:stripe_cardholder)
  end

  def stripe_merchant
    pt&.raw_pending_stripe_transaction&.stripe_transaction&.dig("merchant_data") || ct.raw_stripe_transaction.stripe_transaction["merchant_data"]
  end

  def stripe_merchant_currency
    pt&.raw_pending_stripe_transaction&.stripe_transaction&.dig("merchant_currency") || ct.raw_stripe_transaction.stripe_transaction["merchant_currency"]
  end

  def stripe_refund?
    stripe_force_capture? && ct&.stripe_refund?
  end

  def stripe_auth_dashboard_url
    pt.try(:stripe_auth_dashboard_url) || ct.try(:stripe_auth_dashboard_url)
  end

  def raw_emburse_transaction
    ct&.raw_emburse_transaction
  end

  def emburse_card
    ct&.emburse_card
  end

  def card
    stripe_card || emburse_card
  end

  def bank_fee?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::BANK_FEE_CODE
  end

  def incoming_bank_fee?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::INCOMING_BANK_FEE_CODE
  end

  def fee_revenue?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::FEE_REVENUE_CODE
  end

  def invoice?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::INVOICE_CODE
  end

  def donation?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::DONATION_CODE
  end

  def partner_donation?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::PARTNER_DONATION_CODE
  end

  def ach_transfer?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::ACH_TRANSFER_CODE
  end

  def check?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::CHECK_CODE
  end

  def increase_check?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::INCREASE_CHECK_CODE
  end

  def disbursement?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::DISBURSEMENT_CODE
  end

  def card_grant?
    disbursement? && disbursement&.card_grant.present?
  end

  def grant?
    canonical_pending_transactions.first&.grant.present?
  end

  def stripe_card?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::STRIPE_CARD_CODE
  end

  def stripe_force_capture?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::STRIPE_FORCE_CAPTURE_CODE
  end

  def invoice
    @invoice ||= Invoice.find_by(id: hcb_i2) if invoice?
  end

  def donation
    @donation ||= Donation.find_by(id: hcb_i2) if donation?
  end

  def partner_donation
    @partner_donation ||= PartnerDonation.find_by(id: hcb_i2) if partner_donation?
  end

  def ach_transfer
    @ach_transfer ||= AchTransfer.find_by(id: hcb_i2) if ach_transfer?
  end

  def check
    @check ||= Check.find_by(id: hcb_i2) if check?
  end

  def increase_check
    @increase_check ||= IncreaseCheck.find_by(id: hcb_i2) if increase_check?
  end

  def disbursement
    @disbursement ||= Disbursement.find_by(id: hcb_i2) if disbursement?
  end

  def bank_fee
    @bank_fee ||= BankFee.find_by(id: hcb_i2) if bank_fee?
  end

  def fee_revenue
    @fee_revenue ||= FeeRevenue.find_by(id: hcb_i2) if fee_revenue?
  end

  def ach_payment?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::ACH_PAYMENT_CODE
  end

  def ach_payment
    @ach_payment ||= AchPayment.find(hcb_i2) if ach_payment?
  end

  def check_deposit?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::CHECK_DEPOSIT_CODE
  end

  def outgoing_fee_reimbursement?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::OUTGOING_FEE_REIMBURSEMENT_CODE
  end

  def check_deposit
    @check_deposit ||= CheckDeposit.find_by(id: hcb_i2) if check_deposit?
  end

  def unknown?
    hcb_i1 == ::TransactionGroupingEngine::Calculate::HcbCode::UNKNOWN_CODE
  end

  def hcb_i1
    split_code[1]
  end

  def hcb_i2
    split_code[2]
  end

  def smart_hcb_code
    hcb_code || ::TransactionGroupingEngine::Calculate::HcbCode.new(canonical_transaction_or_canonical_pending_transaction: canonical_transactions.first)
  end

  def split_code
    @split_code ||= smart_hcb_code.split(::TransactionGroupingEngine::Calculate::HcbCode::SEPARATOR)
  end

  def canonical_transaction_ids
    JSON.parse(raw_canonical_transaction_ids)
  end

  def no_transactions?
    !pt && !ct
  end

  def pt
    canonical_pending_transactions.first
  end

  def ct
    canonical_transactions.first
  end

  def ct2
    canonical_transactions.last
  end

  scope :receipt_required, -> {
    joins("LEFT JOIN canonical_pending_transactions ON canonical_pending_transactions.hcb_code = hcb_codes.hcb_code")
      .joins("LEFT JOIN canonical_pending_declined_mappings ON canonical_pending_declined_mappings.canonical_pending_transaction_id = canonical_pending_transactions.id")
      .joins("LEFT JOIN canonical_transactions ON canonical_transactions.hcb_code = hcb_codes.hcb_code")
      .where("canonical_transactions.transaction_source_type = 'RawEmburseTransaction'
              OR (hcb_codes.hcb_code LIKE 'HCB-600%' AND canonical_pending_declined_mappings.id IS NULL)
              OR (hcb_codes.hcb_code LIKE 'HCB-300%' AND hcb_codes.created_at >= '2024-02-01' AND canonical_pending_declined_mappings.id IS NULL)
              OR (hcb_codes.hcb_code LIKE 'HCB-400%' AND hcb_codes.created_at >= '2024-02-01' AND canonical_pending_declined_mappings.id IS NULL)
              ")
  }

  def receipt_required?
    return true if raw_emburse_transaction
    return false if pt&.declined?

    (type == :card_charge) ||
      # starting from Feb. 2024, receipts have been required for ACHs & checks
      ([:ach, :check].include?(type) && created_at > Time.utc(2024, 2, 1))
  end

  def receipt_optional?
    !receipt_required?
  end

  def needs_receipt?
    receipt_required? && marked_no_or_lost_receipt_at.nil? && receipts.size == 0
  end

  def local_hcb_code
    self
  end

  def generate_and_set_short_code
    self.short_code = ::HcbCodeService::Generate::ShortCode.new.run
  end

  def comment_recipients_for(comment)
    users = []
    users += self.comments.map(&:user)
    users += self.events.flat_map(&:users)

    if comment.admin_only?
      users += self.events.map(&:point_of_contact)
      return users.select(&:admin?).collect(&:email).excluding(comment.user.email)
    end

    users.collect(&:email).excluding(comment.user.email)
  end

  def comment_mailer_subject
    return "New comment on #{self.memo}."
  end

  def not_admin_only_comments_count
    # `not_admin_only.count` always issues a new query to the DB because a scope is being applied.
    # However, if comments have been preloaded, it's more likely to be faster to count
    # the non admin comments in memory. The vast majority of HcbCodes have fewer than 4 comments
    @not_admin_only_comments_count ||= if comments.loaded?
                                         comments.count { |c| !c.admin_only }
                                       else
                                         comments.not_admin_only.count
                                       end
  end

  def pinnable?
    !no_transactions? && event
  end

end
