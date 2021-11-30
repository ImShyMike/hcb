# frozen_string_literal: true

module Api
  module V2
    class DonationsNewSerializer
      def initialize(partner_donation:)
        @partner_donation = partner_donation
      end

      def run
        {
          data: data
        }
      end

      private

      def data
        {
          organization_id: organization.public_id,
          donation_id: @partner_donation.public_id,
        }
      end

      def organization
        @partner_donation.event
      end
    end
  end
end
