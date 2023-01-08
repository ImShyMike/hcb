# frozen_string_literal: true

# == Schema Information
#
# Table name: ach_transfers
#
#  id                        :bigint           not null, primary key
#  aasm_state                :string
#  account_number_ciphertext :text
#  amount                    :integer
#  approved_at               :datetime
#  bank_name                 :string
#  confirmation_number       :text
#  payment_for               :text
#  recipient_name            :string
#  recipient_tel             :string
#  rejected_at               :datetime
#  routing_number            :string
#  scheduled_arrival_date    :datetime
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  creator_id                :bigint
#  event_id                  :bigint
#  processor_id              :bigint
#
# Indexes
#
#  index_ach_transfers_on_creator_id    (creator_id)
#  index_ach_transfers_on_event_id      (event_id)
#  index_ach_transfers_on_processor_id  (processor_id)
#
# Foreign Keys
#
#  fk_rails_...  (creator_id => users.id)
#  fk_rails_...  (event_id => events.id)
#
class AchTransfer < ApplicationRecord
  has_paper_trail skip: [:account_number] # ciphertext columns will still be tracked
  has_encrypted :account_number

  include PublicIdentifiable
  set_public_id_prefix :ach

  include AASM
  include Commentable

  include PgSearch::Model
  pg_search_scope :search_recipient, against: [:recipient_name], using: { tsearch: { prefix: true, dictionary: "english" } }, ranked_by: "ach_transfers.created_at"

  belongs_to :creator, class_name: "User"
  belongs_to :processor, class_name: "User", optional: true
  belongs_to :event

  validates :amount, numericality: { greater_than: 0, message: "must be greater than 0" }
  validates_length_of :routing_number, is: 9

  has_one :t_transaction, class_name: "Transaction", inverse_of: :ach_transfer

  scope :approved, -> { where.not(approved_at: nil) }

  aasm do
    state :pending, initial: true
    state :in_transit
    state :rejected
    state :failed
    state :deposited

    event :mark_in_transit do
      transitions from: [:pending, :deposited], to: :in_transit
    end

    event :mark_rejected do
      transitions from: :pending, to: :rejected
    end

    event :mark_failed do
      transitions from: :in_transit, to: :failed
    end

    event :mark_deposited do
      transitions from: :in_transit, to: :deposited
    end
  end

  scope :pending_deprecated, -> { where(approved_at: nil, rejected_at: nil) }
  def self.in_transit_deprecated
    select { |a| a.approved_at.present? && a.t_transaction.nil? }
  end
  scope :rejected_deprecated, -> { where.not(rejected_at: nil) }
  def self.delivered
    select { |a| a.t_transaction.present? }
  end

  def status
    aasm_state.to_sym
  end

  def state_text
    status_text
  end

  def name
    recipient_name
  end

  def status_deprecated
    if t_transaction
      :deposited
    elsif approved_at
      :in_transit
    elsif rejected_at
      :rejected
    elsif pending?
      :pending
    end
  end

  def status_text
    status.to_s.humanize
  end

  def status_text_long
    case status
    when :deposited then "Deposited successfully"
    when :in_transit then "In transit"
    when :pending then "Waiting on Bank approval"
    when :rejected then "Rejected"
    end
  end

  def state
    case status
    when :deposited then :success
    when :in_transit then :info
    when :pending then :pending
    when :rejected then :error
    end
  end

  def filter_data
    {
      exists: true,
      deposited: deposited?,
      in_transit: in_transit?,
      pending: pending?,
      rejected: rejected?
    }
  end

  def state_icon
    "checkmark" if deposited?
  end

  def pending_deprecated?
    approved_at.nil? && rejected_at.nil?
  end

  def approved?
    !pending?
  end

  def rejected_deprecated?
    rejected_at.present?
  end

  def in_transit_deprecated?
    approved_at.present?
  end

  def deposited_deprecated?
    t_transaction.present?
  end

  def admin_dropdown_description
    "#{event.name} - #{recipient_name} | #{ApplicationController.helpers.render_money amount}"
  end

  def approve!
    mark_in_transit!
    update(approved_at: DateTime.now)
  end

  def reject!
    mark_rejected!
    update(rejected_at: DateTime.now)
  end

  def canonical_pending_transaction
    canonical_pending_transactions.first
  end

  def smart_memo
    recipient_name.to_s.upcase
  end

  def canonical_pending_transactions
    @canonical_pending_transactions ||= CanonicalPendingTransaction.where(hcb_code: hcb_code)
  end

  def canonical_transactions
    @canonical_transactions ||= CanonicalTransaction.where(hcb_code: hcb_code)
  end

  def hcb_code
    "HCB-#{TransactionGroupingEngine::Calculate::HcbCode::ACH_TRANSFER_CODE}-#{id}"
  end

  def local_hcb_code
    @local_hcb_code ||= HcbCode.find_or_create_by(hcb_code: hcb_code)
  end

  private

  def raw_pending_outgoing_ach_transaction
    raw_pending_outgoing_ach_transactions.first
  end

  def raw_pending_outgoing_ach_transactions
    @raw_pending_outgoing_ach_transactions ||= ::RawPendingOutgoingAchTransaction.where(ach_transaction_id: id)
  end

end
