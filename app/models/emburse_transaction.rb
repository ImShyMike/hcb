class EmburseTransaction < ApplicationRecord
  enum state: %w{pending completed declined}

  acts_as_paranoid
  validates_as_paranoid

  paginates_per 100

  scope :pending, -> { where(state: 'pending') }
  scope :completed, -> { where(state: 'completed') }
  scope :undeclined, -> { where.not(state: 'declined') }
  scope :declined, -> { where(state: 'declined') }
  scope :under_review, -> { where(event_id: nil).undeclined }

  belongs_to :event, required: false
  belongs_to :card, required: false

  validates_uniqueness_of_without_deleted :emburse_id

  def self.during(start_time, end_time)
    self.where(["emburse_transactions.transaction_time >= ? and emburse_transactions.transaction_time <= ?", start_time, end_time])
  end

  def under_review?
    self.event_id.nil? && undeclined?
  end

  def undeclined?
    state != 'declined'
  end

  def completed?
    state == 'completed'
  end

  def emburse_path
    "https://app.emburse.com/transactions/#{emburse_id}"
  end

  def status_badge_type
    s = state.to_sym
    return :success if s == :completed
    return :error if s == :declined

    :pending
  end

  def status_text
    s = state.to_sym
    return 'Completed' if s == :completed
    return 'Declined' if s == :declined

    'Pending'
  end

  def self.total_card_transaction_volume
    -self.where('amount < 0').completed.sum(:amount)
  end

  def self.total_card_transaction_count
    self.where('amount < 0').completed.size
  end

  def event_running_sum
    EmburseTransaction.undeclined.where(event: event).during(
      event.emburse_transactions.first.transaction_time,
      self.transaction_time
    ).sum(&:amount)
  end
end
