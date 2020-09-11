class StripeController < ApplicationController
  protect_from_forgery except: :webhook # ignore csrf checks
  skip_after_action :verify_authorized # do not force pundit
  skip_before_action :signed_in_user, only: [:webhook] # do not require logged in user

  def webhook
    payload = request.body.read
    event = nil
    
    begin
      event = StripeService::Event.construct_from(
        JSON.parse(payload, symbolize_names: true)
      )
      method = "handle_" + event['type'].tr('.', '_')
      self.send method, event
    rescue JSON::ParserError => e
      head 400
      return
    rescue NoMethodError => e
      puts e
      head 400
      return
    end

    head 200
  end

  private

  def handle_issuing_authorization_request(event)
    auth = event[:data][:object]
    tx_amount = auth[:pending_request][:amount]
    card = StripeCard.find_by(stripe_id: auth[:card][:id])
    should_approve = card.event.balance_available >= tx_amount

    if should_approve
      puts "#{card.event.name} has enough money (#{card.event.balance_available}) for the charge of #{tx_amount}"
      StripeService::Issuing::Authorization.approve(auth[:id])

      StripeAuthorizationMailer.with(auth_obj: auth.to_hash).notify_admin_of_approve.deliver_later
    else
      puts "#{card.event.name} does not have enough (#{card.event.balance_available}) for the charge of #{tx_amount}"
      StripeService::Issuing::Authorization.decline(auth[:id])

      # StripeAuthorization.with(auth_obj: auth).notify_user_of_decline.deliver_now
      StripeAuthorizationMailer.with(auth_obj: auth.to_hash).notify_admin_of_decline.deliver_later
    end
  end

  def handle_issuing_transaction_created(event)
    tx = event[:data][:object]
    amount = tx[:amount]
    return unless amount < 0
    TopupStripeJob.perform_later
  end
end
