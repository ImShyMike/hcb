class GSuiteAccountsController < ApplicationController
  before_action :set_g_suite_account, only: [:edit, :update, :reject, :reset_password, :toggle_suspension]

  def index
    authorize GSuiteAccount

    @under_review = GSuiteAccount.under_review.order(created_at: :desc)
    @g_suite_accounts = GSuiteAccount.all.order(created_at: :desc).page params[:page]
  end

  def create
    @g_suite = GSuite.find(params[:g_suite_id])
    @event = @g_suite.event
    @g_suite_account = GSuiteAccount.new(g_suite_account_params.merge(
      address: full_email_address(params[:g_suite_account][:address], @g_suite),
      creator: current_user,
      g_suite: @g_suite
    ))

    authorize @g_suite_account

    if @g_suite_account.save
      flash[:success] = 'G Suite account application submitted.'
    else
      if @g_suite_account.errors.messages[:domain].present?
        flash[:error] = "Your domain setup is not complete yet."
      else
        flash[:error] = 'That email address is already in use.'
      end
    end

    redirect_to event_g_suite_overview_path(event_id: @event.slug)
  end

  def edit
    authorize @g_suite_account
    @event = @g_suite_account.g_suite.event
  end

  def update
    authorize @g_suite_account

    if @g_suite_account.update(g_suite_account_params)
      if @g_suite_account.previous_changes[:initial_password]
        @g_suite_account.update(accepted_at: Time.now)
        flash[:info] = 'Accepted!'
      end
      flash[:success] = 'Saved changes to G Suite account.'
      redirect_to g_suite_accounts_path
    else
      render :edit
    end
  end

  def destroy
    @g_suite_account = GSuiteAccount.find(params[:id])
    @event = @g_suite_account.g_suite.event

    authorize @g_suite_account

    if @g_suite_account.destroy
      flash[:success] = 'G Suite account deleted successfully.'
    else
      flash[:error] = `Error while trying to delete G Suite account. Please check G Suite dashboard for more information.`
    end

    redirect_to event_g_suite_overview_path(event_id: @event.slug)
  end

  def verify
    email = params[:email]
    @g_suite_account = GSuiteAccount.select { |account| account.full_email_address == email }
    @g_suite_account.verified_at = Time.now
    if @g_suite_account.save
      GSuiteAccountMailer.verify(recipient: @g_suite_account.address).deliver_later
      flash[:success] = 'Email verified!'
      redirect_to @g_suite_account.g_suite.event
    else
      flash[:error] = 'Email not found.'
    end
  end

  # Deprecated: we automatically handle G Suite requests so no applications
  # are rejected.
  def reject
    authorize @g_suite_account

    @g_suite_account.rejected_at = Time.now

    if @g_suite_account.save
      flash[:success] = 'G Suite Account rejected.'
    else
      flash[:error] = 'Something went wrong.'
    end
    redirect_to g_suite_accounts_path
  end

  def reset_password
    authorize @g_suite_account

    @event = @g_suite_account.g_suite.event

    if @g_suite_account.reset_password!
      flash[:success] = "We just sent reset instructions to the backup email for #{@g_suite_account.address}."
      redirect_to event_g_suite_overview_path(event_id: @event.slug)
    else
      flash[:error] = "Something went wrong while trying to reset the password for #{@g_suite_account.address}."
      redirect_to event_g_suite_overview_path(event_id: @event.slug)
    end
  end

  def toggle_suspension
    authorize @g_suite_account

    @event = @g_suite_account.g_suite.event

    if @g_suite_account.toggle_suspension!
      flash[:success] = "#{@g_suite_account.address} has been successfully #{@g_suite_account.suspended? ? 'suspended' : 're-activated'}."
      redirect_to event_g_suite_overview_path(event_id: @event.slug)
    else
      flash[:error] = "Something went wrong while trying to #{@g_suite_account.suspended? ? 'suspended' : 're-activate'} #{@g_suite_account.address}."
      redirect_to event_g_suite_overview_path(event_id: @event.slug)
    end
  end

  private

  def set_g_suite_account
    @g_suite_account = GSuiteAccount.find(params[:g_suite_account_id] || params[:id])
  end

  def g_suite_account_params
    params.require(:g_suite_account).permit(:backup_email, :address, :accepted_at, :rejected_at, :initial_password, :g_suite_id, :first_name, :last_name)
  end

  def full_email_address(address, g_suite)
    "#{address}@#{g_suite.domain}"
  end
end
