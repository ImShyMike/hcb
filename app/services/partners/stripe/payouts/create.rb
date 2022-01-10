# frozen_string_literal: true

module Partners
  module Stripe
    module Payouts
      class Create
        include ::Partners::Stripe::Shared::Opts

        def initialize(stripe_api_key:, amount_cents:, statement_descriptor:, hcb_metadata_identifier:)
          @stripe_api_key = stripe_api_key
          @amount_cents = amount_cents
          @statement_descriptor = statement_descriptor
          @hcb_metadata_identifier = hcb_metadata_identifier
        end

        def run
          ::Stripe::Payout.create(attrs, opts)
        end

        private

        def attrs
          {
            amount: @amount_cents,
            currency: "usd",
            description: @statement_descriptor,
            statement_descriptor: @statement_descriptor,
            metadata: metadata
          }
        end

        def metadata
          {
            hcb_metadata_identifier: @hcb_metadata_identifier
          }
        end

      end
    end
  end
end
