# frozen_string_literal: true

# == Schema Information
#
# Table name: check_deposits
#
#  id               :bigint           not null, primary key
#  amount_cents     :integer
#  increase_status  :string
#  rejection_reason :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  back_file_id     :string
#  column_id        :string
#  created_by_id    :bigint           not null
#  event_id         :bigint           not null
#  front_file_id    :string
#  increase_id      :string
#
# Indexes
#
#  index_check_deposits_on_created_by_id  (created_by_id)
#  index_check_deposits_on_event_id       (event_id)
#  index_check_deposits_on_increase_id    (increase_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#
class CheckDeposit < ApplicationRecord
  REJECTION_DESCRIPTIONS = {
    "incomplete_image"                => "This check was rejected because the photo was incomplete.",
    "duplicate"                       => "This check was rejected as a duplicate.",
    "poor_image_quality"              => "This check was rejected due to poor image quality.",
    "incorrect_amount"                => "This check was rejected because the amount was incorrect.",
    "incorrect_recipient"             => "This check was rejected because the recipient was incorrect.",
    "not_eligible_for_mobile_deposit" => "This check is not eligible for mobile deposit.",
  }.freeze

  monetize :amount_cents

  belongs_to :event
  belongs_to :created_by, class_name: "User"
  has_one :canonical_pending_transaction

  # after_create_commit :submit!
  after_create_commit do
    create_canonical_pending_transaction!(event:, amount_cents:, memo: "CHECK DEPOSIT", date: created_at)
  end

  after_update if: -> { increase_status_previously_changed?(to: "rejected") } do
    canonical_pending_transaction.decline!
    CheckDepositMailer.with(check_deposit: self).rejected.deliver_later
  end

  after_update if: -> { increase_status_previously_changed?(to: "submitted") } do
    canonical_pending_transaction.update(fronted: true)
    CheckDepositMailer.with(check_deposit: self).deposited.deliver_later
  end

  has_one_attached :front
  has_one_attached :back

  validates :amount_cents, numericality: { greater_than: 0, message: "can't be zero!" }, presence: true
  validates :front, attached: true, processable_image: true
  validates :back, attached: true, processable_image: true

  enum :increase_status, {
    pending: "pending",
    submitted: "submitted",
    rejected: "rejected",
    returned: "returned",
  }, default: :pending

  enum :rejection_reason, {
    incomplete_image: "incomplete_image",
    duplicate: "duplicate",
    poor_image_quality: "poor_image_quality",
    incorrect_amount: "incorrect_amount",
    incorrect_recipient: "incorrect_recipient",
    not_eligible_for_mobile_deposit: "not_eligible_for_mobile_deposit",
    unknown: "unknown"
  }, prefix: :rejection_reason

  def submit!
    increase_front = Increase::Files.create(
      purpose: :check_image_front,
      file: StringIO.new(self.front.download.force_encoding("UTF-8")),
    )
    self.front_file_id = increase_front["id"]

    increase_back = Increase::Files.create(
      purpose: :check_image_back,
      file: StringIO.new(self.back.download.force_encoding("UTF-8")),
    )
    self.back_file_id = increase_back["id"]

    increase_check_deposit = Increase::CheckDeposits.create(
      amount: amount_cents,
      currency: "USD",
      account_id: IncreaseService::AccountIds::FS_MAIN,
      front_image_file_id: self.front_file_id,
      back_image_file_id: self.back_file_id,
    )

    self.increase_id = increase_check_deposit["id"]
    self.increase_status = increase_check_deposit["status"]

    self.save!

    create_canonical_pending_transaction!(event:, amount_cents:, memo: "CHECK DEPOSIT", date: created_at)
  end

  def hcb_code
    "HCB-#{TransactionGroupingEngine::Calculate::HcbCode::CHECK_DEPOSIT_CODE}-#{id}"
  end

  def local_hcb_code
    @local_hcb_code ||= HcbCode.find_or_create_by(hcb_code:)
  end

  def state
    if pending?
      :info
    elsif rejected? || returned?
      :error
    elsif submitted?
      :success
    end
  end

  def state_text
    if pending?
      "Pending"
    elsif rejected?
      "Rejected"
    elsif returned?
      "Returned"
    elsif submitted?
      "Deposited"
    end
  end

  def rejection_description
    REJECTION_DESCRIPTIONS[rejection_reason] || "This check deposit was rejected."
  end

end
