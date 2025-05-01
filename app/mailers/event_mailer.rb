# frozen_string_literal: true

class EventMailer < ApplicationMailer
  before_action { @event = params[:event] }
  before_action :set_emails

  def monthly_donation_summary(date: Time.now.last_month)
    @event = params[:event]

    month_range = date.beginning_of_month..date.end_of_month

    @donations = @event.donations.where(aasm_state: [:in_transit, :deposited], created_at: month_range).order(:created_at)

    return if @donations.none?
    return if @emails.none?

    @total = @donations.sum(:amount)

    mail to: @emails, subject: "#{@event.name} received #{@donations.length} donations this past month"
  end

  private

  def set_emails
    @emails = @event.users.map(&:email_address_with_name)
    @emails << @event.config.contact_email if @event.config.contact_email.present?
  end

end
