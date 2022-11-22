# frozen_string_literal: true

FactoryBot.define do
  factory :fee_relationship do
    association :event
    association :t_transaction, factory: :transaction
  end
end
