class ChecksController < ApplicationController
  before_action :set_check, except: %i[index new create export]
  before_action :set_event, only: %i[new create]

  # GET /checks
  def index
    authorize Check
    @checks = Check.all.order(created_at: :desc)
  end

  def export
    authorize Check
    # find all checks that are approved & not exported
    checks = Check.select { |c| !c.exported? && c.approved? }

    attributes = %w{iv account_number check_number amount date}

    result = CSV.generate(headers: true) do |csv|
      csv << attributes.map

      checks.each do |check|
        csv << attributes.map do |attr|
          if attr == 'account_number'
            Rails.application.credentials.positive_pay_account_number
          elsif attr == 'amount'
            check.amount.to_f / 100
          elsif attr == 'date'
            check.approved_at.strftime('%m-%d-%Y')
          elsif attr == 'iv'
            # V tells FRB to void, I is issue
            check.pending_void? || check.refunded? ? "V" : "I"
          else
            check.send(attr)
          end
        end
        check.export!
      end
    end

    send_data result, filename: "Checks #{Date.today}.csv"
  end

  # GET /checks/1
  def show
    authorize @check

    @commentable = @check
    @comments = @commentable.comments
    @comment = Comment.new
  end

  # GET /checks/new
  def new
    @lob_address = LobAddress.new(event: @event)
    @check = Check.new(lob_address: @lob_address)

    authorize @check
  end

  # POST /checks
  def create
    # this pulls apart the lob address and check so they can be created separately
    check_params = filtered_params.except(:action, :controller, :lob_address_attributes)
    check_params[:amount] = filtered_params[:amount].to_f * 100.to_i

    lob_address_params = filtered_params[:lob_address_attributes].merge(event: @event)
    lob_address_params['country'] = 'US'

    @lob_address = LobAddress.find_or_initialize_by(id: lob_address_params[:id], event: @event)

    @check = Check.new(check_params)

    @check.lob_address = @lob_address
    @check.creator = current_user

    authorize @check

    # verify that a user has enough money to write a check
    if @check.amount > @event.balance_available
      flash[:error] = 'You don’t have enough money to write this check!'
      render :new
      return
    end

    if @lob_address.update(lob_address_params) && @check.save
      flash[:success] = 'Submitted your check for approval.'
      redirect_to event_transfers_path(@event)
    else
      render :new
    end
  end

  def edit
    authorize @check

    if @check.approved?
      flash[:error] = "This check has already been issued."
      redirect_to event_transfers_path(@event)
      return
    end

    @event = @check.event
  end

  def start_void
    authorize @check

    if @check.voided?
      flash[:info] = 'You already voided that check!'
      redirect_to event_transfers_path(@check.event)
      return
    end
  end

  def void
    authorize @check

    if @check.voided?
      flash[:success] = 'You already voided that check!'
      redirect_to event_transfers_path(@check.event)
      return false
    end

    if @check.void!
      flash[:success] = 'Check successfully voided.'
      redirect_to event_transfers_path(@check.event)
    else
      render :start_void
    end
  end

  def update
    authorize @check

    if @check.approved?
      flash[:error] = "This check has already been issued!"
      redirect_to event_transfers_path(@event)
      return
    end

    @event = @check.event

    lob_address_params = filtered_params[:lob_address_attributes].merge!(event: @event)
    lob_address_params['country'] = 'US'

    check_params = filtered_params.except(:action, :controller, :lob_address_attributes)
    check_params[:amount] = filtered_params[:amount].to_f * 100.to_i

    if @check.update(check_params) && @check.lob_address.update(lob_address_params)
      flash[:success] = 'Check successfully updated.'
      redirect_to event_transfers_path(@event)
    else
      redirect_to :edit
    end
  end

  def approve
    authorize @check

    if @check.approved?
      flash[:error] = 'This check has already been approved!'
      redirect_to checks_path
      return
    end

    @check.approve!
  end

  def reject
    authorize @check

    if @check.rejected?
      flash[:error] = 'This check has already been rejected!'
      redirect_to checks_path
      return
    end

    @check.reject!

    redirect_to checks_path
  end

  def start_approval
    authorize @check
  end

  def refund_get
    authorize @check
  end

  def refund
    authorize @check

    if @check.refund!
      flash[:sucesss] = "Check has been refunded!"
      redirect_to checks_path
    else
      redirect_to :refund
    end
  end

  private

  def set_check
    @check = Check.includes(:creator).find(params[:id] || params[:check_id])
    @event = @check.event
  end

  def set_event
    @event = Event.find(params[:event_id])
  end

  def filtered_params
    params.require(:check).permit(
      :memo,
      :amount,
      :payment_for,
      :lob_address_id,
      lob_address_attributes: [
        :name,
        :address1,
        :address2,
        :city,
        :state,
        :zip,
        :id
      ]
    )
  end
end
