# frozen_string_literal: true

class V2DonationsDocumentation < ApplicationDocumentation
  swagger_path "/api/v2/donations/new" do
    operation :post do
      key :summary, "Start a donation backed by Bank"
      key :description, "Start a donation backed by Bank"
      key :tags, ["Donations"]
      key :operationId, "v2DonationsNew"

      parameter do
        key :name, :organization_id
        key :in, :query
        key :description, "The Bank Connect organization's id"
        key :required, true
        schema do
          key :type, :string
        end
      end

      response 200 do
        key :description, "Parse this **Donation** object in order to inject the `donation_id` into the **Stripe Payment Intent** metadata as `hcb_metadata_identifier`"
        content :"application/json" do
          key :example,
              data:
                    {
                      organization_id: "org_s2cDsp",
                      donation_id: "pdn_Lsl39s",
                    }
        end
      end
    end
  end

end
