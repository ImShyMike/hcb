# frozen_string_literal: true

require "rails_helper"

RSpec.describe Donation, type: :modal do
  include ActiveJob::TestHelper

  it "is valid" do
    donation = create(:donation)
    expect(donation).to be_valid
  end

  it "sends a payment notification on first donation paid" do
    event = create(:event)

    expect do
      donation = create(:donation, event:)
      donation.status = "succeeded"
      donation.save
    end.to change(enqueued_jobs, :size).by(1)
  end

  it "does not send notifications for later donations" do
    event = create(:event)

    expect do
      donation = create(:donation, event:)
      donation.status = "succeeded"
      donation.save

      donation2 = create(:donation, event:)
      donation2.status = "succeeded"
      donation2.save

      donation3 = create(:donation, event:)
      donation3.status = "succeeded"
      donation3.save
      donation3.delete
    end.to change(enqueued_jobs, :size).by(1)
  end

  it "does not send multiple email notifications" do
    event = create(:event)

    expect do
      donation = create(:donation, event:)
      donation.status = "succeeded"
      donation.save

      donation.status = "succeeded"
      donation.save
    end.to change(enqueued_jobs, :size).by(1)
  end

  it "does not send email notifications for non-succeeded donations" do
    event = create(:event)

    expect do
      donation = create(:donation, event:, name: "John Appleseed", email: "john@hackclub.com")
    end.to change(enqueued_jobs, :size).by(0)
  end

end
