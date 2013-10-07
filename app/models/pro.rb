class Pro < Subscription
  include PerAgent
  def campaign_types
    [Campaign::Type::PREVIEW, Campaign::Type::POWER, Campaign::Type::PREDICTIVE]
  end

  def campaign_type_options
    [[Campaign::Type::PREVIEW, Campaign::Type::PREVIEW], [Campaign::Type::POWER, Campaign::Type::POWER], [Campaign::Type::PREDICTIVE, Campaign::Type::PREDICTIVE]]
  end

  def transfer_types
    [Transfer::Type::WARM, Transfer::Type::COLD]
  end

  def minutes_per_caller
    2500.00
  end

  def price_per_caller
    99.00
  end

  def caller_groups_enabled?
    true
  end

  def campaign_reports_enabled?
    true
  end

  def caller_reports_enabled?
    true
  end

  def call_recording_enabled?
    false
  end

  def dashboard_enabled?
    true
  end

  def can_dial?
    available_minutes > 0
  end


  def debit(call_time)
    updated_minutes = minutes_utlized + call_time
    self.update_attributes(minutes_utlized: updated_minutes)
  end

  def subscribe(upgrade=true)
    disable_call_recording    
    self.total_allowed_minutes = upgrade ? calculate_minutes_on_upgrade : account.available_minutes
    self.minutes_utlized = upgrade ? 0 : account.minutes_utlized
  end

end