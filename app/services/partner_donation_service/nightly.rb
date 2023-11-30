# frozen_string_literal: true

module PartnerDonationService
  class Nightly
    def run
      # 1. import partner donations
      ::Partner.all.each do |partner|
        ::PartnerDonationService::Import.new(partner_id: partner.id).run
      end

      # 2. mark anything in transit that now has a settled transaction as deposited
      PartnerDonation.in_transit.find_each(batch_size: 100) do |partner_donation|
        cpt = partner_donation.canonical_pending_transaction

        next unless cpt
        next unless cpt.settled?

        raise ArgumentError, "anomaly detected when attempting to mark deposited partner donation #{partner_donation.id}" if anomaly_detected?(partner_donation:)

        begin
          partner_donation.mark_deposited!
        rescue => e
          Airbrake.notify(e)
        end
      end
    end

    private

    def anomaly_detected?(partner_donation:)
      ::PendingEventMappingEngine::AnomalyDetection::BadSettledMapping.new(canonical_pending_transaction: partner_donation.canonical_pending_transaction).run
    end

  end
end
