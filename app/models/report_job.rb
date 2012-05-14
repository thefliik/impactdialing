class ReportJob 
  
  def initialize(campaign, user, voter_fields, custom_fields, all_voters,lead_dial, from, to, callback_url, strategy="webui")
    @campaign = campaign
    @user = user
    @selected_voter_fields = voter_fields
    @selected_custom_voter_fields = custom_fields
    @download_all_voters = all_voters
    @lead_dial = lead_dial
    @from_date = from
    @to_date = to
    @callback_url = callback_url
    @strategy = strategy
    @selected_voter_fields = ["Phone"] if @selected_voter_fields.blank?
  end

  def save_report
    AWS::S3::Base.establish_connection!(
        :access_key_id => 'AKIAINGDKRFQU6S63LUQ',
        :secret_access_key => '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'
    )

    FileUtils.mkdir_p(Rails.root.join("tmp"))
    uuid = UUID.new.generate
    @campaign_name = "#{uuid}_report_#{@campaign.name}"
    @campaign_name = @campaign_name.tr("/\000", "")
    filename = "#{Rails.root}/tmp/#{@campaign_name}.csv"
    report_csv = @report.split("\n")
    puts "Writing to file: #{report_csv.size}"
    file = File.open(filename, "w")
    report_csv.each do |r|
      begin
        file.write(r)
        file.write("\n")
      rescue Exception => e
        puts "row from report"
        puts r
        puts e
        next
      end      
    end
    file.close    
    expires_in_12_hours = (Time.now + 12.hours).to_i
    AWS::S3::S3Object.store("#{@campaign_name}.csv", File.open(filename), "download_reports", :content_type => "application/binary", :access=>:private, :expires => expires_in_12_hours)
  end

  def perform
    @campaign_strategy = @campaign.robo ? BroadcastStrategy.new(@campaign) : CallerStrategy.new(@campaign)    
    @report = CSV.generate do |csv|
      csv << @campaign_strategy.csv_header(@selected_voter_fields, @selected_custom_voter_fields)
      if @download_all_voters
        if @lead_dial == "dial"
          @campaign.call_attempts.find_in_batches(:batch_size => 100) { |attempts| attempts.each { |a| csv << csv_for_call_attempt(a) } }
        else
          @campaign.all_voters.find_in_batches(:batch_size => 100) { |voters| voters.each { |v| csv << csv_for(v) } }
        end        
      else
        if @lead_dial == "dial"
          @campaign.call_attempts.between(@from_date, @to_date).find_in_batches(:batch_size => 100) { |call_attempts| call_attempts.each { |a| csv << csv_for_call_attempt(a) } }
        else
          @campaign.all_voters.last_call_attempt_within(@from_date, @to_date).find_in_batches(:batch_size => 100) { |voters| voters.each { |v| csv << csv_for(v) } }
        end
        
      end
    end
    save_report
    
  end

  def csv_for(voter)
    puts "Voter_ID: #{voter.id}"
    voter_fields = voter.selected_fields(@selected_voter_fields.try(:compact))
    custom_fields = voter.selected_custom_fields(@selected_custom_voter_fields)
    [voter_fields, custom_fields, @campaign_strategy.call_details(voter)].flatten
  end
  
  def csv_for_call_attempt(call_attempt)
    puts "CallAttempt_ID: #{call_attempt.id}"
    voter = call_attempt.voter
    voter_fields = voter.selected_fields(@selected_voter_fields.try(:compact))
    custom_fields = voter.selected_custom_fields(@selected_custom_voter_fields)
    [voter_fields, custom_fields, @campaign_strategy.call_attempt_details(call_attempt, voter)].flatten
  end
  

  def after(job)
    notify_success
  end

  def error(job, exception)
    notify_failure(job, exception)
  end

  def notify_success
    response_strategy = @strategy == 'webui' ?  ReportWebUIStrategy.new("success", @user, @campaign, nil, nil) : ReportApiStrategy.new("failure", @campaign.id, @campaign.account.id, @callback_url)
    response_strategy.response({campaign_name: @campaign_name})
  end

  def notify_failure(job, exception)
    response_strategy = strategy == 'webui' ?  ReportWebUIStrategy.new("failure", @user, @campaign, job, exception) : ReportApiStrategy.new("failure", @campaign.id, @campaign.account.id, @callback_url)
    response_strategy.response({})
  end

end

class CampaignStrategy
  def initialize(campaign)
    @campaign = campaign
  end
end


class CallerStrategy < CampaignStrategy
  def csv_header(fields, custom_fields)
    [fields, custom_fields, "Caller", "Status", "Call start", "Call end", "Attempts", "Recording", @campaign.script.questions.collect { |q| q.text }, @campaign.script.notes.collect { |note| note.note }].flatten.compact
  end
  
  def call_attempt_details(call_attempt, voter)
    answers, notes = [], []
    details = [call_attempt.try(:caller).try(:known_as), call_attempt.status, call_attempt.try(:call_start).try(:in_time_zone, @campaign.time_zone), call_attempt.try(:call_end).try(:in_time_zone, @campaign.time_zone), 1, call_attempt.try(:report_recording_url)].flatten
    @campaign.script.questions.each { |q| answers << call_attempt.answers.for(q).first.try(:possible_response).try(:value) }
    @campaign.script.notes.each { |note| notes << call_attempt.note_responses.for(note).last.try(:response) }
    [details, answers, notes].flatten
    
  end

  def call_details(voter)
    answers, notes = [], []
    last_attempt = voter.call_attempts.last
    details = if last_attempt
                [last_attempt.try(:caller).try(:known_as), voter.status, last_attempt.try(:call_start).try(:in_time_zone, @campaign.time_zone), last_attempt.try(:call_end).try(:in_time_zone, @campaign.time_zone), voter.call_attempts.size, last_attempt.try(:report_recording_url)].flatten
              else
                [nil, "Not Dialed","","","",""]
              end
    @campaign.script.questions.each { |q| answers << voter.answers.for(q).last.try(:possible_response).try(:value) }
    @campaign.script.notes.each { |note| notes << voter.note_responses.for(note).last.try(:response) }
    [details, answers, notes].flatten
  end
end

class BroadcastStrategy < CampaignStrategy
  def csv_header(fields, custom_fields)
    [fields, custom_fields, "Status", @campaign.script.robo_recordings.collect { |rec| rec.name }].flatten.compact
  end
  
  def call_attempt_details(call_attempt, voter)
    [call_attempt.status, (call_attempt.call_responses.collect { |call_response| call_response.recording_response.try(:response) } if call_attempt.call_responses.size > 0)].flatten
  end

  def call_details(voter)
    last_attempt = voter.call_attempts.last
    details = last_attempt ? [last_attempt.status, (last_attempt.call_responses.collect { |call_response| call_response.recording_response.try(:response) } if last_attempt.call_responses.size > 0)].flatten : ['Not Dialed']
    details
  end
end

class ReportWebUIStrategy
  
  def initialize(result, user, campaign, job, exception)
    @result = result
    @mailer = UserMailer.new    
    @user = user
    @campaign = campaign
    @job = job
    @exception = exception
  end

    
  def response(params)
    if @result == "success"
      expires_in_12_hours = (Time.now + 12.hours).to_i
      link = AWS::S3::S3Object.url_for("#{params[:campaign_name]}.csv", "download_reports", :expires => expires_in_12_hours)
      DownloadedReport.create(link: link, user: @user, campaign_id: @campaign.id)
      @mailer.deliver_download(@user, link)
    else
      @mailer.deliver_download_failure(@user, @campaign, @job, @exception)
    end
  end
  
end


class ReportApiStrategy
  require 'net/http'
  
  def initialize(result, account_id, campaign_id, callback_url)
    @result = result
    @account_id = account_id
    @campaign_id = campaign_id
    @callback_url = callback_url
  end
  
  def response(params)
    if @result == "success"
      link = AWS::S3::S3Object.url_for("#{params[:campaign_name]}.csv", "download_reports", :expires => expires_in_12_hours)
    else
      link = ""
    end
    uri = URI.parse(@callback_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl=true
    request = Net::HTTP::Post.new(uri.request_uri)
    request.set_form_data({message: @result, download_link: link, account_id: @account_id, campaign_id: @campaign_id})
    http.start{http.request(request)}
  end
  
end
