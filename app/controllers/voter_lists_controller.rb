require 'tempfile'
require Rails.root.join("jobs/voter_list_upload_job")

class VoterListsController < ClientController
  layout 'v2'

  before_filter :load_and_verify_campaign
  before_filter :load_voter_list, :only=> [:show, :enable, :disable, :update]
  respond_to :html
  respond_to :json, :only => [:index, :create, :show, :update, :destroy]

  def index
    respond_with(@campaign.voter_lists, :only => [:id, :name, :enabled])
  end

  def show
    respond_with(@voter_list, :only => [:id, :name, :enabled])
  end

  def enable
    @voter_list.enabled = true
    @voter_list.save
    respond_with @voter_list,  location: campaign_voter_lists_path(@campaign) do |format|
      format.json { render :json => {message: "Voter List enabled" }, :status => :ok } if @voter_list.errors.empty?
    end
  end

  def disable
    @voter_list.enabled = false
    @voter_list.save
    respond_with @voter_list,  location: campaign_voter_lists_path(@campaign) do |format|
      format.json { render :json => {message: "Voter List disabled" }, :status => :ok } if @voter_list.errors.empty?
    end
  end

  def update
    @voter_list.update_attributes(params[:voter_list])
    respond_with @voter_list,  location: campaign_voter_lists_path(@campaign) do |format|
      format.json { render :json => {message: "Voter List updated" }, :status => :ok } if @voter_list.errors.empty?
    end
  end

  def destroy
    render :json=> {"message"=>"This opeartion is not permitted"}, :status => :method_not_allowed
  end


  def create
    upload = params[:upload].try(:[], "datafile")
    s3path = VoterList.upload_file_to_s3(upload.try('read'), VoterList.csv_file_name(params[:voter_list][:name]))
    params[:voter_list][:s3path] = s3path
    params[:voter_list][:uploaded_file_name] = upload.try('original_filename')
    params[:voter_list][:csv_to_system_map] = params[:voter_list][:csv_to_system_map].to_json
    voter_list = @campaign.voter_lists.new(params[:voter_list])

    respond_with(voter_list, location:  edit_client_campaign_path(@campaign.id)) do |format|
      if voter_list.save
        flash_message(:notice, I18n.t(:voter_list_upload_scheduled))
        Resque.enqueue(VoterListUploadJob, voter_list.id, "impactdialing", current_user.email,"")
        format.json { render :json => voter_list.to_json(:only => ["id", "name", "enabled"])}
      else
        flash_message(:error, voter_list.errors.full_messages.join)
        format.html { redirect_to edit_client_campaign_path(@campaign.id)}
      end
    end

  end

  def column_mapping
    if params[:extension] == 'txt'
      @csv_column_headers = params[:headers].join("\t").split("\t")
      @first_data_row = params[:first_data_row].join("\t").split("\t")
    else
      @csv_column_headers = params[:headers]
      @first_data_row = params[:first_data_row]
    end
    render layout: false
  end

  private


  def load_voter_list
    begin
      @voter_list = @campaign.voter_lists.find(params[:id])
    rescue ActiveRecord::RecordNotFound => e
      render :json=> {"message"=>"Resource not found"}, :status => :not_found
      return
    end
  end


  def load_and_verify_campaign
    begin
      @campaign = Campaign.find(params[:campaign_id])
    rescue ActiveRecord::RecordNotFound => e
      render :json=> {"message"=>"Resource not found"}, :status => :not_found
      return
    end
    if @campaign.account != account
      render :json => {message: 'Cannot access campaign.'}, :status => :unauthorized
      return
    end

  end


  def setup_based_on_type
    @layout = 'client'
    @campaign_path = client_campaign_path(@campaign)
  end
end
