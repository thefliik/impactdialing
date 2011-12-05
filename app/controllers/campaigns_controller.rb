class CampaignsController < ClientController
  layout 'v2'
  include DeletableController
  before_filter :verify_campaign_ownership, :only => [:update, :show, :start, :stop, :dial_statistics, :destroy]
  before_filter :setup_campaigns_paths, :only => [:index]

  def verify_campaign_ownership
    @campaign = Campaign.find(params[:id])
    if @campaign.account != account
      render :text => 'nothing', :status => :unauthorized
    end
  end

  def type_name
    'campaign'
  end

  def create
    campaign = @user.account.campaigns.create!(:script => @user.account.scripts.robo.first, :robo => true, :caller_id => params[:caller_id])
    redirect_to broadcast_campaign_path(campaign)
  end

  def update
    @campaign.attributes = params[:campaign]
    @campaign.script ||= account.scripts.active.first
    @campaign.voter_lists.disable_all
    @campaign.voter_lists.by_ids(params[:voter_list_ids]).enable_all

    if @campaign.valid?
      flash_message(:notice, "Campaign saved") if @campaign.save
      redirect_to campaign_path(@campaign)
    else
      @scripts = @user.account.scripts.robo.active
      @callers = account.callers.active
      @lists = @campaign.voter_lists
      @voters = @campaign.all_voters.active.paginate(:page => params[:page])
      @voter_list = @campaign.voter_lists.new
      render :show
    end

  end

  def destroy
    @campaign.update_attribute(:active, false)
    flash_message(:notice, "Campaign deleted")
    redirect_to :back
  end

  def index
    @campaigns = active_robo_campaigns
  end

  def show
    unless @campaign.robo?
      redirect_to client_campaign_path(@campaign)
      return
    end
    @scripts = @user.account.scripts.robo.active
    @callers = account.callers.active
    @lists = @campaign.voter_lists
    @voters = @campaign.all_voters.active.paginate(:page => params[:page])
    @voter_list = @campaign.voter_lists.new
  end

  def control
    @campaigns = active_robo_campaigns
  end

  def running_status
    render :partial => "control_list", :locals => {:campaigns => active_robo_campaigns}
  end

  def start
    @campaign.start
    redirect_to control_campaigns_path
  end

  def stop
    @campaign.stop
    redirect_to control_campaigns_path
  end

  def dial_statistics
  end

  private
  def generate_validation_token_for_caller_id(campaign)
    validation_code = campaign.caller_id_object.validation_code
    if validation_code
      flash_message(:notice, "<font color=red>Please enter code #{validation_code} when called.</font>")
    else
      flash_message(:error, "Could not validate your caller id")
    end
  end

  def active_robo_campaigns
    account.campaigns.active.robo.paginate :page => params[:page], :order => 'id desc'
  end

  def load_campaign
    @campaign = account.all_campaigns.find(params[:campaign_id] || params[:id])
  end

  def setup_campaigns_paths
    @deleted_campaigns_path = client_deleted_campaigns_path
    @campaigns_path = campaigns_path
  end
end
