# frozen_string_literal: true

require "csv"

class DonationsController < ApplicationController
  include Rails::Pagination
  skip_after_action :verify_authorized
  skip_before_action :signed_in_user
  before_action :set_donation, only: [:show]
  before_action :set_event, only: [:start_donation, :make_donation, :finish_donation, :qr_code]
  before_action :allow_iframe, except: [:show, :index]

  invisible_captcha only: [:make_donation], honeypot: :subtitle, on_timestamp_spam: :redirect_to_404

  # GET /donations/1
  def show
    authorize @donation
    @hcb_code = HcbCode.find_or_create_by(hcb_code: @donation.hcb_code)
    redirect_to hcb_code_path(@hcb_code.hashid)
  end

  def start_donation
    if !@event.donation_page_enabled
      return not_found
    end

    @donation = Donation.new(amount: params[:amount])
  end

  def make_donation
    d_params = public_donation_params
    d_params[:amount] = (public_donation_params[:amount].to_f * 100.to_i)

    @donation = Donation.new(d_params)
    @donation.event = @event

    if @donation.save
      redirect_to finish_donation_donations_path(@event, @donation.url_hash)
    else
      render "start_donation"
    end
  end

  def finish_donation
    @donation = Donation.find_by!(url_hash: params["donation"])

    if @donation.status == "succeeded"
      flash[:info] = "You tried to access the payment page for a donation that’s already been sent."
      redirect_to start_donation_donations_path(@event)
    end
  end

  def accept_donation_hook
    payload = request.body.read
    sig_header = request.headers['Stripe-Signature']
    event = nil

    begin
      event = StripeService.construct_webhook_event(payload, sig_header)
    rescue Stripe::SignatureVerificationError
      head 400
      return
    end

    # only proceed if payment intent is a donation and not an invoice
    return unless event.data.object.metadata[:donation].present?

    # get donation to process
    donation = Donation.find_by_stripe_payment_intent_id(event.data.object.id)

    pi = StripeService::PaymentIntent.retrieve(
      id: donation.stripe_payment_intent_id,
      expand: ["charges.data.balance_transaction"]
    )
    donation.set_fields_from_stripe_payment_intent(pi)
    donation.save!

    DonationService::Queue.new(donation_id: donation.id).run # queues/crons payout. DEPRECATE. most is unnecessary if we just run in a cron

    donation.send_receipt!

    return true
  end

  def qr_code
    qrcode = RQRCode::QRCode.new(start_donation_donations_url(@event))

    png = qrcode.as_png(
      bit_depth: 1,
      border_modules: 2,
      color_mode: ChunkyPNG::COLOR_GRAYSCALE,
      color: "black",
      fill: "white",
      module_px_size: 6,
      size: 300
    )

    send_data png, filename: "#{@event.name} Donate.png",
      type: "image/png", disposition: "inline"
  end

  def refund
    @donation = Donation.find(params[:id])
    @hcb_code = @donation.local_hcb_code

    ::DonationJob::Refund.perform_later(@donation.id)

    redirect_to hcb_code_path(@hcb_code.hashid), flash: { success: "The refund process has been queued for this donation." }
  end

  def export
    @event = Event.friendly.find(params[:event])

    authorize @event.donations.first

    respond_to do |format|
      format.csv { stream_donations_csv }
      format.json { stream_donations_json }
    end
  end

  private

  def stream_donations_csv
    set_file_headers_csv
    set_streaming_headers

    response.status = 200

    self.response_body = donations_csv
  end

  def stream_donations_json
    set_file_headers_json
    set_streaming_headers

    response.status = 200

    self.response_body = donations_json
  end

  def set_file_headers_csv
    headers["Content-Type"] = "text/csv"
    headers["Content-disposition"] = "attachment; filename=donations.csv"
  end

  def set_file_headers_json
    headers["Content-Type"] = "application/json"
    headers["Content-disposition"] = "attachment; filename=donations.json"
  end

  def donations_csv
    ::DonationService::Export::Csv.new(event_id: @event.id).run
  end

  def donations_json
    ::DonationService::Export::Json.new(event_id: @event.id).run
  end

  def set_event
    @event = Event.find(params["event_name"])
  end

  def set_donation
    @donation = Donation.find(params[:id])
  end

  # Only allow a trusted parameter "white list" through.
  def donation_params
    params.require(:donation).permit(:email, :name, :amount, :amount_received, :status, :stripe_client_secret)
  end

  def public_donation_params
    params.require(:donation).permit(:email, :name, :amount, :message)
  end

  def allow_iframe
    response.headers["X-Frame-Options"] = "ALLOWALL"
  end

  def redirect_to_404
    raise ActionController::RoutingError.new("Not Found")
  end

end
