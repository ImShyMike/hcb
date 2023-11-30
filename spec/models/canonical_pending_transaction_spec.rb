# frozen_string_literal: true

require "rails_helper"

RSpec.describe CanonicalPendingTransaction, type: :model do
  let(:canonical_pending_transaction) { create(:canonical_pending_transaction) }

  it "is valid" do
    expect(canonical_pending_transaction).to be_valid
  end

  describe "hcb_code" do
    let(:canonical_pending_transaction) {
      create(:canonical_pending_transaction)
    }
    let(:hcb_code) { canonical_pending_transaction.reload.hcb_code }

    it "calculates it on create" do
      expect(hcb_code).to eql("HCB-000-#{canonical_pending_transaction.id}")
    end

    context "when a raw_pending_stripe_transaction is attached" do
      let(:raw_pending_stripe_transaction) { create(:raw_pending_stripe_transaction) }

      let(:canonical_pending_transaction) {
        create(:canonical_pending_transaction,
               raw_pending_stripe_transaction:)
      }

      it "returns it" do
        rpst = canonical_pending_transaction.raw_pending_stripe_transaction

        expect(rpst).to eql(raw_pending_stripe_transaction)
      end

      it "calculates a different hcb code" do
        expect(hcb_code).to eql("HCB-600-#{raw_pending_stripe_transaction.stripe_transaction_id}")
      end
    end
  end

  describe "#event" do
    let(:event) { create(:event) }
    let(:canonical_pending_transaction) { create(:canonical_pending_transaction) }

    before do
      CanonicalPendingEventMapping.create!(event:, canonical_pending_transaction:)
    end

    it "returns event" do
      expect(canonical_pending_transaction.event).to be_present
      expect(canonical_pending_transaction.event).to eq(event)
    end
  end

  describe "#stripe_card" do
    let!(:raw_pending_stripe_transaction) { create(:raw_pending_stripe_transaction) }
    let!(:canonical_pending_transaction) { create(:canonical_pending_transaction, raw_pending_stripe_transaction:) }
    let!(:stripe_card) { create(:stripe_card, :with_stripe_id, stripe_id: raw_pending_stripe_transaction.stripe_transaction["card"]["id"]) }

    it "returns stripe card" do
      sc = canonical_pending_transaction.stripe_card

      expect(sc).to eql(stripe_card)
    end
  end

  describe "#search_memo" do
    context "when the memo is a partial match for the search query" do
      it "still finds the transaction" do
        canonical_pending_transaction = create(:canonical_pending_transaction, memo: "POSTAGE GOSHIPPO.COM")
        expect(CanonicalPendingTransaction.search_memo("go shippo")).to contain_exactly(canonical_pending_transaction)
      end
    end
  end
end
