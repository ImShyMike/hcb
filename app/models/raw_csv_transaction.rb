# frozen_string_literal: true

# == Schema Information
#
# Table name: raw_csv_transactions
#
#  id                     :bigint           not null, primary key
#  amount_cents           :integer
#  date_posted            :date
#  memo                   :text
#  raw_data               :jsonb
#  unique_bank_identifier :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  csv_transaction_id     :text
#
# Indexes
#
#  index_raw_csv_transactions_on_csv_transaction_id  (csv_transaction_id) UNIQUE
#
class RawCsvTransaction < ApplicationRecord
  has_many :hashed_transactions

  scope :unhashed, -> { left_joins(:hashed_transactions).where(hashed_transactions: { raw_csv_transaction_id: nil }) }

  monetize :amount_cents

end
