# frozen_string_literal: true

class HcbCodesController < ApplicationController
  include TagsHelper

  skip_before_action :signed_in_user, only: [:receipt, :attach_receipt, :show]
  skip_after_action :verify_authorized, only: [:receipt]

  def show
    @hcb_code = HcbCode.find_by(hcb_code: params[:id]) || HcbCode.find(params[:id])
    @event =
      begin
        # Attempt to retrieve the event using the context of the
        # previous page. Has a high chance of erroring, but we'll give it
        # a shot.
        route = Rails.application.routes.recognize_path(request.referrer)
        model = route[:controller].classify.constantize
        object = model.find(route[:id])
        event = model == Event ? object : object.event
        raise StandardError unless @hcb_code.events.include? event

        event
      rescue
        @hcb_code.events.min_by do |e|
          [e.users.include?(current_user), e.is_public?].map { |b| b ? 0 : 1 }
        end
      rescue
        @hcb_code.event
      end

    hcb = @hcb_code.hcb_code
    hcb_id = @hcb_code.hashid

    authorize @hcb_code

    if params[:show_details] == "true" && @hcb_code.ach_transfer?
      ahoy.track "ACH details shown", hcb_code_id: @hcb_code.id
      @show_ach_details = true
    end

    if params[:frame]
      @frame = true
      render :show, layout: false
    else
      @frame = false
      render :show
    end
  rescue Pundit::NotAuthorizedError => e
    raise unless @event.is_public? && !params[:redirect_to_sign_in]

    if @hcb_code.canonical_transactions.any?
      txs = TransactionGroupingEngine::Transaction::All.new(event_id: @event.id).run
      pos = txs.index { |tx| tx.hcb_code == hcb } + 1
      page = (pos.to_f / 100).ceil

      redirect_to event_path(@event, page:, anchor: hcb_id)
    else
      redirect_to event_path(@event, anchor: hcb_id)
    end
  end

  def memo_frame
    @hcb_code = HcbCode.find(params[:id])
    authorize @hcb_code

    if params[:gen_memo]
      @ai_memo = HcbCodeService::AiGenerateMemo.new(hcb_code: @hcb_code).run
    end
  end

  def edit
    @hcb_code = HcbCode.find_by(hcb_code: params[:id]) || HcbCode.find(params[:id])
    @event = @hcb_code.event

    authorize @hcb_code

    if params[:inline].present?
      return render partial: "hcb_codes/memo", locals: { hcb_code: @hcb_code, form: true, prepended_to_memo: params[:prepended_to_memo] }
    end

    @frame = turbo_frame_request?
    @suggested_memos = [::HcbCodeService::AiGenerateMemo.new(hcb_code: @hcb_code).run].compact + ::HcbCodeService::SuggestedMemos.new(hcb_code: @hcb_code, event: @event).run.first(4)
  end

  def update
    @hcb_code = HcbCode.find_by(hcb_code: params[:id]) || HcbCode.find(params[:id])

    authorize @hcb_code
    hcb_code_params = params.require(:hcb_code).permit(:memo, :prepended_to_memo)
    hcb_code_params[:memo] = hcb_code_params[:memo].presence

    @hcb_code.canonical_transactions.each { |ct| ct.update!(custom_memo: hcb_code_params[:memo]) }
    @hcb_code.canonical_pending_transactions.each { |cpt| cpt.update!(custom_memo: hcb_code_params[:memo]) }

    if params[:hcb_code][:inline].present?
      return render partial: "hcb_codes/memo", locals: { hcb_code: @hcb_code, form: false, prepended_to_memo: params[:hcb_code][:prepended_to_memo], renamed: true }
    end

    redirect_to @hcb_code
  end

  def comment
    @hcb_code = HcbCode.find(params[:id])

    authorize @hcb_code

    ::HcbCodeService::Comment::Create.new(
      hcb_code_id: @hcb_code.id,
      content: params[:content],
      file: params[:file],
      admin_only: params[:admin_only],
      current_user:
    ).run

    redirect_to params[:redirect_url]
  rescue => e
    redirect_to params[:redirect_url], flash: { error: e.message }
  end

  include HcbCodeHelper # for disputed_transactions_airtable_form_url and attach_receipt_url

  def attach_receipt
    @hcb_code = HcbCode.find(params[:id])
    @event = @hcb_code.event
    @secret = params[:s]

    authorize @hcb_code

  rescue Pundit::NotAuthorizedError
    raise unless HcbCode.find_signed(@secret, purpose: :receipt_upload) == @hcb_code
  end

  def send_receipt_sms
    @hcb_code = HcbCode.find(params[:id])

    authorize @hcb_code

    cpt = @hcb_code.canonical_pending_transactions.first

    CanonicalPendingTransactionJob::SendTwilioReceiptMessage.perform_now(cpt_id: cpt.id, user_id: current_user.id)

    flash[:success] = "SMS queued for delivery!"
    redirect_back fallback_location: @hcb_code
  end

  def dispute
    @hcb_code = HcbCode.find(params[:id])

    authorize @hcb_code

    can_dispute, error_reason = ::HcbCodeService::CanDispute.new(hcb_code: @hcb_code).run

    if can_dispute
      redirect_to disputed_transactions_airtable_form_url(embed: false, hcb_code: @hcb_code, user: @current_user), allow_other_host: true
    else
      redirect_to @hcb_code, flash: { error: error_reason }
    end
  end

  def toggle_tag
    hcb_code = HcbCode.find(params[:id])
    tag = Tag.find(params[:tag_id])
    @event = tag.event

    authorize hcb_code
    authorize tag

    raise Pundit::NotAuthorizedError unless hcb_code.events.include?(tag.event)

    removed = false

    if hcb_code.tags.exists?(tag.id)
      removed = true
      hcb_code.tags.destroy(tag)
    else
      hcb_code.tags << tag
    end

    respond_to do |format|
      format.turbo_stream do
        if removed
          render turbo_stream: turbo_stream.remove(tag_dom_id(hcb_code, tag)) + turbo_stream.update_all(tag_dom_class(hcb_code, tag, "_toggle"), tag.label)
        else
          render turbo_stream: turbo_stream.append("hcb_code_#{hcb_code.hashid}_tags", partial: "canonical_transactions/tag", locals: { tag:, hcb_code: }) + turbo_stream.update_all(tag_dom_class(hcb_code, tag, "_toggle"), "✓ " + tag.label)
        end
      end
      format.any { redirect_back fallback_location: @event }
    end
  end

  def invoice_as_personal_transaction
    hcb_code = HcbCode.find(params[:id])
    event = hcb_code.event
    spender = hcb_code.stripe_cardholder&.user || current_user

    authorize hcb_code

    return render plain: "404 Not found", status: :not_found if !event&.hack_club_hq? || spender.nil?

    @invoice = ::InvoiceService::Create.new(
      event_id: event.id,
      due_date: 1.month.from_now,
      item_description: "Reimbursing personal transaction: #{hcb_code.memo}",
      item_amount: hcb_code.amount.abs,
      current_user:,
      sponsor_id: nil,
      sponsor_name: spender.name,
      sponsor_email: spender.email,
      sponsor_address_line1: spender.stripe_cardholder.stripe_billing_address_line1,
      sponsor_address_line2: spender.stripe_cardholder.stripe_billing_address_line2,
      sponsor_address_city: spender.stripe_cardholder.stripe_billing_address_city,
      sponsor_address_state: spender.stripe_cardholder.stripe_billing_address_state,
      sponsor_address_postal_code: spender.stripe_cardholder.stripe_billing_address_postal_code,
      sponsor_address_country: spender.stripe_cardholder.stripe_billing_address_country
    ).run

    ::HcbCodeService::Comment::Create.new(
      hcb_code_id: @invoice.local_hcb_code.id,
      content: "#{hcb_code_url(hcb_code)} was marked as an accidental misuse.",
      current_user:
    ).run

    ::HcbCodeService::Comment::Create.new(
      hcb_code_id: hcb_code.id,
      content: "This transaction was marked as an accidental misuse. Reimbursement requested at #{hcb_code_url(@invoice.local_hcb_code)}.",
      current_user:
    ).run

    flash[:success] = "We've sent an invoice for repayment to #{@invoice.sponsor.contact_email}."

    redirect_to @invoice
  end

end
