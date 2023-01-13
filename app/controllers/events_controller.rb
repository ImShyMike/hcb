# frozen_string_literal: true

class EventsController < ApplicationController
  include SetEvent

  include Rails::Pagination
  before_action :set_event, except: [:index, :new, :create, :by_airtable_id]
  before_action except: [:show, :index] do
    render_back_to_tour @organizer_position, :welcome, event_path(@event)
  end
  skip_before_action :signed_in_user

  # GET /events
  def index
    authorize Event

    @event_ids_with_transactions_cache = FeeRelationship.distinct.pluck(:event_id) # for performance reasons - until we build proper counter caching and modify schemas a bit for easier calculations
    @events = Event.all
  end

  # GET /events/1
  def show
    render_tour @organizer_position, :welcome

    authorize @event

    # The search query name was historically `search`. It has since been renamed
    # to `q`. This following line retains backwards compatibility.
    params[:q] ||= params[:search]

    if params[:tag] && Flipper.enabled?(:transaction_tags_2022_07_29, @event)
      @tag = Tag.find_by(event_id: @event.id, label: params[:tag])
    end

    @organizers = @event.organizer_positions.includes(:user).order(created_at: :desc).limit(5)
    @pending_transactions = _show_pending_transactions

    if !signed_in? && !@event.holiday_features
      @hide_holiday_features = true
    end

    @transactions = Kaminari.paginate_array(TransactionGroupingEngine::Transaction::All.new(event_id: @event.id, search: params[:q], tag_id: @tag&.id).run).page(params[:page]).per(params[:per] || 75)
    TransactionGroupingEngine::Transaction::AssociationPreloader.new(transactions: @transactions, event: @event).run!
  end

  def fees
    authorize @event

    @fees = @event.fees.includes(canonical_event_mapping: :canonical_transaction).order("canonical_transactions.date desc, canonical_transactions.id desc")
  end

  # async frame for incoming money
  def dashboard_stats
    authorize @event

    render :dashboard_stats, layout: false
  end

  # GET /event_by_airtable_id/recABC
  def by_airtable_id
    authorize Event
    @event = Event.find_by(club_airtable_id: params[:airtable_id])

    if @event.nil?
      flash[:error] = "We couldn’t find that event!"
      redirect_to root_path
    else
      redirect_to @event
    end
  end

  def team
    authorize @event
    @positions = @event.organizer_positions.includes(:user).order(created_at: :desc)
    @pending = @event.organizer_position_invites.pending.includes(:sender)
  end

  # GET /events/1/edit
  def edit
    authorize @event

    @color = ["info", "success", "warning", "accent", "error"].sample
    @flavor = ["jank", "janky", "wack", "wacky", "hack", "hacky"].sample
  end

  # PATCH/PUT /events/1
  def update
    authorize @event

    # have to use `fixed_event_params` because `event_params` seems to be a constant
    fixed_event_params = event_params
    fixed_user_event_params = user_event_params

    fixed_event_params[:club_airtable_id] = nil if event_params.key?(:club_airtable_id) && event_params[:club_airtable_id].empty?

    # processing hidden for admins
    if fixed_event_params[:hidden] == "1" && !@event.hidden_at.present?
      fixed_event_params[:hidden_at] = DateTime.now
    elsif fixed_event_params[:hidden] == "0" && @event.hidden_at.present?
      fixed_event_params[:hidden_at] = nil
    end
    fixed_event_params.delete(:hidden)

    # processing hidden for users
    if fixed_user_event_params[:hidden] == "1" && !@event.hidden_at.present?
      fixed_user_event_params[:hidden_at] = DateTime.now
    elsif fixed_user_event_params[:hidden] == "0" && @event.hidden_at.present?
      fixed_user_event_params[:hidden_at] = nil
    end
    fixed_user_event_params.delete(:hidden)

    if @event.update(current_user.admin? ? fixed_event_params : fixed_user_event_params)
      flash[:success] = "Organization successfully updated."
      redirect_back fallback_location: edit_event_path(@event.slug)
    else
      render "edit"
    end
  end

  # DELETE /events/1
  def destroy
    authorize @event

    @event.destroy
    flash[:success] = "Project successfully destroyed."
    redirect_to events_url
  end

  def emburse_card_overview
    @event = Event.includes([
                              { emburse_cards: :user },
                              { emburse_transfers: [:t_transaction, :creator] }
                            ]).find(params[:event_id])
    authorize @event
    @emburse_cards = @event.emburse_cards.includes(user: [:profile_picture_attachment])
    @emburse_card_requests = @event.emburse_card_requests.includes(creator: :profile_picture_attachment)
    @emburse_transfers = @event.emburse_transfers
    @emburse_transactions = @event.emburse_transactions.order(transaction_time: :desc).where.not(transaction_time: nil).includes(:emburse_card)

    @sum = @event.emburse_balance
  end

  def card_overview
    @stripe_cards = @event.stripe_cards.includes(:stripe_cardholder, :user).order("created_at desc")
    @session_user_stripe_card = []

    unless current_user.nil?
      @session_user_stripe_cards = @stripe_cards.filter { |card| card.user.id.eql?(current_user.id) }
      @stripe_cards = @stripe_cards.filter { |card| !card.user.id.eql?(current_user.id) }
    end

    @stripe_cardholders = StripeCardholder.where(user_id: @event.users.pluck(:id)).includes(:user).order("created_at desc")

    authorize @event
  end

  def documentation
    @event_name = @event.name

    authorize @event
  end

  def async_balance
    authorize @event

    render :async_balance, layout: false
  end

  # (@msw) these pages are for the WIP resources page.
  def connect_gofundme
    @event_name = @event.name
    @document_title = "Connect a GoFundMe Campaign"
    @document_subtitle = "Receive payouts from GoFundMe directly into Hack Club Bank"
    @document_image = "https://cloud-jl944nr65-hack-club-bot.vercel.app/004e072bbe1.png"
    authorize @event
  end

  # (@msw) these pages are for the WIP resources page.
  def receive_check
    @event_name = @event.name
    @document_title = "Receive Checks"
    @document_subtitle = "Deposit checks into your Hack Club Bank account"
    @document_image = "https://cloud-9sk4no7es-hack-club-bot.vercel.app/0slaps-jpg-this-image-can-hold-so-many-pixels.avi.onion.gif.7zip.msw.jpg"
    authorize @event
  end

  # (@msw) these pages are for the WIP resources page.
  def sell_merch
    event_name = @event.name
    @document_title = "Sell Merch with Redbubble"
    @document_subtitle = "Connect your online merch shop to Hack Club Bank"
    @document_image = "https://cloud-fodxc88eu-hack-club-bot.vercel.app/0placeholder.png"
    authorize @event
  end

  def g_suite_overview
    authorize @event

    @g_suite = @event.g_suites.first
  end

  def g_suite_create
    authorize @event

    attrs = {
      current_user: current_user,
      event_id: @event.id,
      domain: params[:domain]
    }
    GSuiteService::Create.new(attrs).run

    redirect_to event_g_suite_overview_path(event_id: @event.slug)
  rescue => e
    redirect_to event_g_suite_overview_path(event_id: @event.slug), flash: { error: e.message }
  end

  def g_suite_verify
    authorize @event

    GSuiteService::MarkVerifying.new(g_suite_id: @event.g_suites.first.id).run

    redirect_to event_g_suite_overview_path(event_id: @event.slug)
  end

  def donation_overview
    authorize @event

    # The search query name was historically `search`. It has since been renamed
    # to `q`. This following line retains backwards compatibility.
    params[:q] ||= params[:search]

    relation = @event.donations.not_pending

    @stats = {
      # Amount we already deposited + partial amount that was deposit for in transit transactions
      deposited: relation.deposited.sum(:amount) + relation.in_transit.sum(&:amount_settled),
      # Amount in transit minus the amount that is already settled
      in_transit: relation.in_transit.sum(:amount) - relation.in_transit.sum(&:amount_settled),
      refunded: relation.refunded.sum(:amount)
    }

    relation = relation.in_transit if params[:filter] == "in_transit"
    relation = relation.deposited if params[:filter] == "deposited"
    relation = relation.refunded if params[:filter] == "refunded"
    relation = relation.search_name(params[:q]) if params[:q].present?

    @donations = relation.order(created_at: :desc)
  end

  def partner_donation_overview
    authorize @event

    relation = @event.partner_donations.not_unpaid

    @stats = {
      deposited: relation.deposited.sum(:payout_amount_cents),
      in_transit: relation.in_transit.sum(:payout_amount_cents),
    }

    relation = relation.pending if params[:filter] == "pending"
    relation = relation.in_transit if params[:filter] == "in_transit"
    relation = relation.deposited if params[:filter] == "deposited"

    @partner_donations = relation.order(created_at: :desc)
  end

  def demo_mode_request_meeting
    authorize @event

    @event.demo_mode_request_meeting_at = Time.current

    if @event.save!
      OperationsMailer.with(event_id: @event.id).demo_mode_request_meeting.deliver_later
      flash[:success] = "We've received your request. We'll be in touch soon!"
    else
      flash[:error] = "Something went wrong. Please try again."
    end

    redirect_to @event
  end

  def bank_fees
    authorize @event

    relation1 = @event.bank_fees

    relation1 = relation1.in_transit if params[:filter] == "in_transit"
    relation1 = relation1.settled if params[:filter] == "settled"

    @bank_fees = relation1.order("created_at desc")
  end

  def transfers
    authorize @event

    # The search query name was historically `search`. It has since been renamed
    # to `q`. This following line retains backwards compatibility.
    params[:q] ||= params[:search]

    @transfers_enabled = Flipper.enabled?(:transfers_2022_04_21, current_user)
    @ach_transfers = @event.ach_transfers
    @checks = @event.checks.includes(:lob_address)
    @disbursements = @transfers_enabled ? @event.outgoing_disbursements.includes(:destination_event) : Disbursement.none

    @stats = {
      deposited: @ach_transfers.deposited.sum(:amount) + @checks.deposited.sum(:amount) + @disbursements.fulfilled.pluck(:amount).sum,
      in_transit: @ach_transfers.in_transit.sum(:amount) + @checks.in_transit_or_in_transit_and_processed.sum(:amount) + @disbursements.reviewing_or_processing.sum(:amount),
      canceled: @ach_transfers.rejected.sum(:amount) + @checks.canceled.sum(:amount) + @disbursements.rejected.sum(:amount)
    }

    @ach_transfers = @ach_transfers.in_transit if params[:filter] == "in_transit"
    @ach_transfers = @ach_transfers.deposited if params[:filter] == "deposited"
    @ach_transfers = @ach_transfers.rejected if params[:filter] == "canceled"
    @ach_transfers = @ach_transfers.search_recipient(params[:q]) if params[:q].present?

    @checks = @checks.in_transit_or_in_transit_and_processed if params[:filter] == "in_transit"
    @checks = @checks.deposited if params[:filter] == "deposited"
    @checks = @checks.canceled if params[:filter] == "canceled"
    @checks = @checks.search_recipient(params[:q]) if params[:q].present?

    if @transfers_enabled
      @disbursements = @disbursements.reviewing_or_processing if params[:filter] == "in_transit"
      @disbursements = @disbursements.fulfilled if params[:filter] == "deposited"
      @disbursements = @disbursements.rejected if params[:filter] == "canceled"
      @disbursements = @disbursements.search_name(params[:q]) if params[:q].present?
    end

    @transfers = Kaminari.paginate_array((@checks + @ach_transfers + @disbursements).sort_by { |o| o.created_at }.reverse!).page(params[:page]).per(100)
  end

  def new_transfer
    authorize @event
  end

  def promotions
    authorize @event
  end

  def reimbursements
    authorize @event
  end

  def toggle_hidden
    authorize @event

    if @event.hidden?
      flash[:success] = "Event un-hidden"
      @event.update(hidden_at: nil)
    else
      @event.update(hidden_at: Time.now)
      file_redirects = [
        "https://cloud-b01qqxaux.vercel.app/barking_dog_turned_into_wood_meme.mp4",
        "https://cloud-b01qqxaux.vercel.app/dog_transforms_after_seeing_chair.mp4",
        "https://cloud-b01qqxaux.vercel.app/dog_turns_into_bread__but_it_s_in_hd.mp4",
        "https://cloud-b01qqxaux.vercel.app/run_now_meme.mp4",
        "https://cloud-3qup26j81.vercel.app/bonk_sound_effect.mp4",
        "https://cloud-is6jebpbb.vercel.app/disappearing_doge_meme.mp4"
      ].sample

      redirect_to file_redirects
    end
  end

  def remove_header_image
    authorize @event

    @event.donation_header_image.purge_later

    redirect_back fallback_location: edit_event_path(@event)
  end

  def remove_logo
    authorize @event

    @event.logo.purge_later

    redirect_back fallback_location: edit_event_path(@event)
  end

  def enable_feature
    authorize @event
    feature = params[:feature]
    if Flipper.enable_actor(feature, @event)
      flash[:success] = "Opted into beta"
    else
      flash[:error] = "Error while opting into beta"
    end
    redirect_to edit_event_path(@event)
  end

  def disable_feature
    authorize @event
    feature = params[:feature]
    if Flipper.disable_actor(feature, @event)
      flash[:success] = "Opted out of beta"
    else
      flash[:error] = "Error while opting out of beta"
    end
    redirect_to edit_event_path(@event)
  end

  private

  # Only allow a trusted parameter "white list" through.
  def event_params
    result_params = params.require(:event).permit(
      :name,
      :start,
      :end,
      :address,
      :sponsorship_fee,
      :expected_budget,
      :omit_stats,
      :demo_mode,
      :can_front_balance,
      :emburse_department_id,
      :country,
      :category,
      :organized_by_hack_clubbers,
      :club_airtable_id,
      :point_of_contact_id,
      :slug,
      :beta_features_enabled,
      :hidden,
      :donation_page_enabled,
      :donation_page_message,
      :is_public,
      :is_indexable,
      :holiday_features,
      :public_message,
      :custom_css_url,
      :donation_header_image,
      :logo
    )

    # Expected budget is in cents on the backend, but dollars on the frontend
    result_params[:expected_budget] = result_params[:expected_budget].to_f * 100 if result_params[:expected_budget]
    # convert whatever the user inputted into something that is a legal slug
    result_params[:slug] = ActiveSupport::Inflector.parameterize(user_event_params[:slug]) if result_params[:slug]

    result_params
  end

  def user_event_params
    result_params = params.require(:event).permit(
      :address,
      :slug,
      :hidden,
      :start,
      :end,
      :donation_page_enabled,
      :donation_page_message,
      :is_public,
      :is_indexable,
      :holiday_features,
      :public_message,
      :custom_css_url,
      :donation_header_image,
      :logo
    )

    # convert whatever the user inputted into something that is a legal slug
    result_params[:slug] = ActiveSupport::Inflector.parameterize(result_params[:slug]) if result_params[:slug]

    result_params
  end

  def _show_pending_transactions
    return [] if params[:page] && params[:page] != "1"
    return [] unless using_transaction_engine_v2? && using_pending_transaction_engine?

    pending_transactions = PendingTransactionEngine::PendingTransaction::All.new(event_id: @event.id, search: params[:q], tag_id: @tag&.id).run
    PendingTransactionEngine::PendingTransaction::AssociationPreloader.new(pending_transactions: pending_transactions, event: @event).run!
    pending_transactions
  end

end
