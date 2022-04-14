# frozen_string_literal: true

require "net/http"

class StaticPagesController < ApplicationController
  skip_after_action :verify_authorized # do not force pundit
  skip_before_action :signed_in_user, only: [:stats, :stats_custom_duration, :project_stats, :branding, :faq]

  def index
    if signed_in?
      attrs = {
        current_user: current_user
      }
      @service = StaticPageService::Index.new(attrs)

      @events = @service.events
      @invites = @service.invites
    end
    if admin_signed_in?
      @transaction_volume = CanonicalTransaction.included_in_stats.sum("@amount_cents")
    end
  end

  def branding
    @logos = [
      { name: "Original Light", criteria: "For white or light colored backgrounds.", background: "smoke" },
      { name: "Original Dark", criteria: "For black or dark colored backgrounds.", background: "black" },
      { name: "Outlined Black", criteria: "For white or light colored backgrounds.", background: "snow" },
      { name: "Outlined White", criteria: "For black or dark colored backgrounds.", background: "black" }
    ]
    @icons = [
      { name: "Icon Original", criteria: "The original Hack Club Bank logo.", background: "smoke" },
      { name: "Icon Dark", criteria: "Hack Club Bank logo in dark mode.", background: "black" }
    ]
    @event_name = signed_in? && current_user.events.first ? current_user.events.first.name : "Hack Pennsylvania"
  end

  def faq
  end

  def my_cards
    flash[:success] = "Card activated!" if params[:activate]
    @stripe_cards = current_user.stripe_cards.includes(:event)
    @emburse_cards = current_user.emburse_cards.includes(:event)
  end

  # async frame
  def my_missing_receipts_list
    @missing_receipt_ids = []
    current_user.stripe_cards.map do |card|
      break unless @missing_receipt_ids.size < 5

      card.hcb_codes.without_receipt.pluck(:id).each do |id|
        @missing_receipt_ids << id
        break unless @missing_receipt_ids.size < 5
      end
    end
    @missing = HcbCode.where(id: @missing_receipt_ids)
    if @missing.any?
      render :my_missing_receipts_list, layout: !request.xhr?
    else
      head :ok
    end
  end

  def my_inbox
    stripe_cards = current_user.stripe_cards.includes(:event)
    emburse_cards = current_user.emburse_cards.includes(:event)

    @cards = (stripe_cards + emburse_cards).filter { |card| card.hcb_codes.missing_receipt.length > 0 }
    @count = @cards.sum { |card| card.hcb_codes.missing_receipt.length }
  end

  def project_stats
    slug = params[:slug]

    event = Event.find_by(is_public: true, slug: slug)

    return render plain: "404 Not found", status: 404 unless event

    raised = event.canonical_transactions.revenue.sum(:amount_cents)

    render json: {
      raised: raised
    }
  end

  def stats_custom_duration
    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : DateTime.new(2015, 1, 1)
    end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : DateTime.current

    render json: CanonicalTransactionService::Stats::During.new(start_time: start_date, end_time: end_date).run
  end

  def stats
    now = params[:date].present? ? Date.parse(params[:date]) : DateTime.current
    year_ago = now - 1.year
    qtr_ago = now - 3.month
    month_ago = now - 1.month
    week_ago = now - 1.week

    events_list = Event.not_omitted
                       .where("created_at <= ?", now)
                       .order(created_at: :desc)
                       .limit(10)
                       .pluck(:created_at)
                       .map(&:to_i)
                       .map { |time| { created_at: time } }

    tx_all = CanonicalTransaction.included_in_stats.where("date <= ?", now)

    render json: {
      date: now,
      events_count: Event.not_omitted.not_hidden.approved.where("created_at <= ?", now).size,
      last_transaction_date: tx_all.order(:date).last.date.to_time.to_i,

      # entire time period. this remains to prevent breaking changes to existing systems that use this endpoint
      raised: tx_all.revenue.sum(:amount_cents),
      transactions_count: tx_all.size,
      transactions_volume: tx_all.sum("@amount_cents"),

      # entire (all), year, quarter, and month time periods
      all: CanonicalTransactionService::Stats::During.new.run,
      last_year: CanonicalTransactionService::Stats::During.new(start_time: year_ago, end_time: now).run,
      last_qtr: CanonicalTransactionService::Stats::During.new(start_time: qtr_ago, end_time: now).run,
      last_month: CanonicalTransactionService::Stats::During.new(start_time: month_ago, end_time: now).run,
      last_week: CanonicalTransactionService::Stats::During.new(start_time: week_ago, end_time: now).run,

      # events
      events: events_list,
    }
  end

  def stripe_charge_lookup
    charge_id = params[:id]
    @payment = Invoice.find_by(stripe_charge_id: charge_id)

    # No invoice with that charge id? Maybe we can find a donation payment with that charge?
    # Donations don't store charge id, but they store payment intent, and we can link it with the charge's payment intent on stripe
    unless @payment
      payment_intent_id = StripeService::Charge.retrieve(charge_id)["payment_intent"]
      @payment = Donation.find_by(stripe_payment_intent_id: payment_intent_id)
    end

    @event = @payment.event

    render json: {
      event_id: @event.id,
      event_name: @event.name,
      payment_type: @payment.class.name,
      payment_id: @payment.id
    }
  rescue StripeService::InvalidRequestError => e
    render json: {
      event_id: nil
    }
  end

end
