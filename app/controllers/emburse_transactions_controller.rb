class EmburseTransactionsController < ApplicationController
  before_action :set_emburse_transaction, only: [:edit, :update]
  skip_before_action :signed_in_user

  def index
    authorize EmburseTransaction
    @all_et = EmburseTransaction.undeclined.order(created_at: :desc).page params[:page]
    @emburse_transactions = @all_et.where(event_id: nil) + @all_et.where.not(event_id: nil)
  end

  def edit
    @amount = @emburse_transaction.amount / 100.0

    # when pairing positive Emburse transactions, it's sometimes useful to be
    # able to cross check with the latest LCRs because most positive Emburse TXs
    # are load card requests. Shown to admins on amount > 0 only.
    @load_card_requests = LoadCardRequest.accepted.order(created_at: :desc).limit(10)
  end

  def update
    result_params = emburse_transaction_params
    result_params[:amount] = result_params[:amount].to_f * 100.0
    if @emburse_transaction.update(result_params)
      if result_params[:amount] > 0 && @emburse_transaction.event.present?
        # it's generally a LCR
        flash[:success] = 'Emburse Transaction updated.'
        flash[:error] = 'You should update the Emburse budget now.'
        redirect_to event_cards_overview_path(@emburse_transaction.event.slug)
      else
        # it's generally a card transaction
        flash[:success] = 'Emburse Transaction successfully updated.'
        redirect_to emburse_transactions_path
      end
    else
      render :edit
    end
  end

  def show
    @emburse_transaction = EmburseTransaction.includes(:event, card: :user).find(params[:id])
    authorize @emburse_transaction

    @commentable = @emburse_transaction
    @comments = @commentable.comments.includes(:user)
    @comment = Comment.new

    @card = @emburse_transaction.card
    @event = @emburse_transaction.event
  end

  private

  def emburse_transaction_params
    params.require(:emburse_transaction).permit(:amount, :event_id)
  end

  def set_emburse_transaction
    @emburse_transaction = EmburseTransaction.find(params[:id])
    authorize @emburse_transaction
  end
end
