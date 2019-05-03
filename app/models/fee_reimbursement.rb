class FeeReimbursement < ApplicationRecord
  has_one :invoice
  has_one :t_transaction, class_name: 'Transaction', inverse_of: :fee_reimbursement
  has_many :comments, as: :commentable

  before_create :default_values

  # SVB has a 30 character limit for transfer descriptions
  validates_length_of :transaction_memo, maximum: 30
  validates_uniqueness_of :transaction_memo

  scope :unprocessed, -> { includes(:t_transaction).where(processed_at: nil, transactions: { fee_reimbursement_id: nil }) }
  scope :pending, -> { where.not(processed_at: nil) }
  scope :completed, -> { includes(:t_transaction).where.not(transactions: { fee_reimbursement_id: nil }) }
  scope :failed, -> { where('processed_at < ?', Time.now - 5.days).pending }

  def unprocessed?
    processed_at.nil? && t_transaction.nil?
  end

  def pending?
    !processed_at.nil?
  end

  def completed?
    !t_transaction.nil?
  end

  def status
    return 'completed' if completed?
    return 'pending' if pending?

    'unprocessed'
  end

  def status_color
    return 'success' if completed?
    return 'info' if pending?

    'error'
  end

  def process
    processed_at = DateTime.now
  end

  def transfer_amount
    [self.amount, 100].max
  end

  def default_values
    self.transaction_memo ||= "FEE REIMBURSEMENT #{Time.now.to_i}"
    self.amount ||= self.invoice.item_amount - self.invoice.payout_creation_balance_net
  end
end
