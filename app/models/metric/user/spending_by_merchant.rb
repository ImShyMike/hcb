# frozen_string_literal: true

# == Schema Information
#
# Table name: metrics
#
#  id           :bigint           not null, primary key
#  metric       :jsonb
#  subject_type :string
#  type         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  subject_id   :bigint
#
# Indexes
#
#  index_metrics_on_subject  (subject_type,subject_id)
#
class Metric
  module User
    class SpendingByMerchant < Metric
      include Subject

      def calculate
        RawStripeTransaction.select(
          "CASE
             WHEN raw_stripe_transactions.stripe_transaction->'merchant_data'->>'name' SIMILAR TO '(SQ|GOOGLE|TST|RAZ|INF|PayUp|IN|INT|\\*)%'
               THEN TRIM(UPPER(raw_stripe_transactions.stripe_transaction->'merchant_data'->>'name'))
             ELSE TRIM(UPPER(SPLIT_PART(raw_stripe_transactions.stripe_transaction->'merchant_data'->>'name', '*', 1)))
           END AS merchant_name",
          "SUM(raw_stripe_transactions.amount_cents) * -1 AS amount_spent"
        )
                            .joins("JOIN stripe_cardholders on raw_stripe_transactions.stripe_transaction->>'cardholder' = stripe_cardholders.stripe_id")
                            .where("EXTRACT(YEAR FROM date_posted) = ?", 2023)
                            .where(stripe_cardholders: { user_id: user.id })
                            .group(
                              "CASE
               WHEN raw_stripe_transactions.stripe_transaction->'merchant_data'->>'name' SIMILAR TO '(SQ|GOOGLE|TST|RAZ|INF|PayUp|IN|INT|\\*)%'
                 THEN TRIM(UPPER(raw_stripe_transactions.stripe_transaction->'merchant_data'->>'name'))
               ELSE TRIM(UPPER(SPLIT_PART(raw_stripe_transactions.stripe_transaction->'merchant_data'->>'name', '*', 1)))
             END"
                            )
                            .order(Arel.sql("SUM(raw_stripe_transactions.amount_cents) * -1 DESC"))
                            .each_with_object({}) { |item, hash| hash[item[:merchant_name]] = item[:amount_spent] }
      end

    end
  end

end
