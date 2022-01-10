# frozen_string_literal: true

require "csv"

module CanonicalTransactionService
  module Export
    class Csv
      BATCH_SIZE = 1000

      def initialize(event_id:)
        @event_id = event_id
      end

      def run
        Enumerator.new do |y|
          y << header.to_s

          event.canonical_transactions.order("date desc").each do |ct|
            y << row(ct).to_s
          end
        end
      end

      private

      def event
        @event ||= Event.find(@event_id)
      end

      def header
        ::CSV::Row.new(headers, ["date", "memo", "amount_cents"], true)
      end

      def row(ct)
        ::CSV::Row.new(headers, [ct.date, ct.smart_memo, ct.amount_cents])
      end

      def headers
        [:date, :memo, :amount_cents]
      end

    end
  end
end
