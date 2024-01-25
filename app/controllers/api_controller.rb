# frozen_string_literal: true

class ApiController < ApplicationController
  before_action :check_token
  before_action :set_params
  skip_before_action :verify_authenticity_token # do not use CSRF token checking for API routes
  skip_after_action :verify_authorized # do not force pundit
  skip_before_action :signed_in_user

  rescue_from(ActiveRecord::RecordNotFound) { render json: { error: "Record not found" }, status: :not_found }

  # find an event by slug
  def event_find
    # pull slug out from JSON
    slug = params[:slug]

    e = Event.find_by_slug(slug)

    # event not found
    if e.nil?
      render json: { error: "Not Found" }, status: :not_found
      return
    end

    render json: {
      name: e.name,
      organizer_emails: e.users.pluck(:email),
      total_balance: e.balance / 100
    }
  end

  def disbursement_new
    expecting = ["source_event_slug", "destination_event_slug", "amount", "name"]
    got = params.keys
    missing = []

    expecting.each do |e|
      if !got.include? e
        missing.push(e)
      end

      expecting.delete(e)
    end

    if missing.size > 0
      render json: {
        error: "Missing #{missing}"
      }, status: :bad_request
      return
    end

    source_event_slug = params[:source_event_slug]
    destination_event_slug = params[:destination_event_slug]
    amount = params[:amount].to_f * 100
    name = params[:name]

    target_event = Event.find_by_slug(destination_event_slug)

    if !target_event
      render json: { error: "Couldn't find target event!" }, status: :not_found
      return
    end

    d = Disbursement.new(
      event: target_event,
      source_event: Event.find(source_event_slug),
      amount:,
      name:
    )

    if !d.save
      render json: { error: "Disbursement couldn't be created! #{d.errors.full_messages}" }, status: :internal_server_error
      return
    end

    render json: {
      source_event_slug:,
      destination_event_slug:,
      amount: amount.to_f / 100,
      name:
    }, status: :created
  end

  def create_demo_event
    event = EventService::CreateDemoEvent.new(
      name: params[:name],
      email: params[:email],
      country: params[:country],
      category: params[:category],
      is_public: params[:transparent].nil? ? true : params[:transparent],
    ).run

    result = {}
    status = 200
    if event&.errors&.any?
      result.error = event.errors
      status = 422
    else
      result[:name] = event.name
      result[:slug] = event.slug
      result[:email] = params[:email]
      result[:transparent] = event.is_public?
    end

    render json: result, status:
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { error: e }, status: :unprocessable_entity
  end

  def user_find
    user = User.find_by_email!(params[:email])
    recent_transactions = if user.stripe_cardholder.present?
                            RawPendingStripeTransaction.where("stripe_transaction->>'cardholder' = ?", user.stripe_cardholder.stripe_id)
                                                       .order(Arel.sql("stripe_transaction->>'created' DESC"))
                                                       .limit(10)
                                                       .includes(canonical_pending_transaction: [:canonical_pending_declined_mapping, :local_hcb_code])
                                                       .map do |t|
                                                         {
                                                           memo: t.memo,
                                                           date: t.date_posted,
                                                           declined: t.canonical_pending_transaction.declined?,
                                                           id: t.canonical_pending_transaction.local_hcb_code.hashid,
                                                           amount: t.amount_cents,
                                                         }
                                                       end
                          else
                            []
                          end

    render json: {
      name: user.name,
      email: user.email,
      slug: user.slug,
      id: user.id,
      orgs: user.events.not_hidden.map { |e| { name: e.name, slug: e.slug, demo: e.demo_mode?, balance: e.balance_available } },
      card_count: user.stripe_cards.count,
      recent_transactions:,
      timezone: user.user_sessions.where.not(timezone: nil).order(created_at: :desc).first&.timezone,
    }
  end

  private

  def check_token
    attempt_api_token = request.headers["Authorization"]&.split(" ")&.last
    if attempt_api_token != Rails.application.credentials.api_token
      render json: { error: "Unauthorized" }, status: :unauthorized
      return
    end
  end

  def set_params
    @params = ActiveSupport::JSON.decode(request.body.read)
  rescue JSON::ParserError
    render json: { error: "Invalid JSON body" }, status: :unauthorized
  end

end
