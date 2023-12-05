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
  module Event
    class TotalRaised < Metric
      include Subject

      def calculate
        TransactionGroupingEngine::Transaction::All.new(event_id: self.event.id, revenue: true).sum.abs
      end

    end
  end

end
