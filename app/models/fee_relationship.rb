class FeeRelationship < ApplicationRecord
  belongs_to :event
  has_one :t_transaction, class_name: 'Transaction', inverse_of: :fee_relationship

  # these two are mutually exclusive
  validates :fee_applies, inclusion: { in: [false] }, if: :is_fee_payment
  validates :is_fee_payment, inclusion: { in: [false] }, if: :fee_applies

  validates :fee_amount, presence: true, if: :fee_applies

  after_initialize :default_values
  before_validation :calculate_fee

  def default_values
    self.fee_applies ||= false
    self.is_fee_payment ||= false
  end

  def calculate_fee
    return if self.fee_amount

    amount = self.t_transaction.amount
    fee = self.event.sponsorship_fee

    if amount > 0 && self.fee_applies
      self.fee_amount = fee * amount
    end
  end

  def fee_percent
    return nil unless self.fee_applies

    self.fee_amount / BigDecimal.new(self.t_transaction.amount)
  end
end
