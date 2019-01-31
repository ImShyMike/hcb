class SponsorsController < ApplicationController
  before_action :set_sponsor, only: [:show, :edit, :update, :destroy]

  # GET /sponsors
  def index
    authorize Sponsor
    @sponsors = Sponsor.all.includes(:event)
  end

  # GET /sponsors/1
  def show
    authorize @sponsor
  end

  # GET /sponsors/1/edit
  def edit
    authorize @sponsor
  end

  # POST /sponsors
  def create
    @sponsor = Sponsor.new(sponsor_params)
    @sponsor.event_id = params[:sponsor][:event_id] # one-time allow users to set the event
    authorize @sponsor

    if @sponsor.save
      flash[:success] = 'Sponsor was successfully created.'
      redirect_to @sponsor
    else
      render :new
    end
  end

  # PATCH/PUT /sponsors/1
  def update
    @sponsor.attributes = sponsor_params
    authorize @sponsor

    if @sponsor.save
      flash[:success] = 'Sponsor was successfully updated.'
      redirect_to @sponsor
    else
      render :edit
    end
  end

  # DELETE /sponsors/1
  def destroy
    authorize @sponsor

    @sponsor.destroy
    flash[:success] = 'Sponsor was successfully destroyed.'
    redirect_to sponsors_url
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_sponsor
    @sponsor = Sponsor.find(params[:id])
    @event = @sponsor.event
  end

  # Only allow a trusted parameter "white list" through.
  def sponsor_params
    # see pundit readme for details on permitted_attributes
    params.require(:sponsor).permit(policy(Sponsor).permitted_attributes)
  end
end
