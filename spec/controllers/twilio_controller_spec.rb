require "spec_helper"

describe TwilioController do
  let(:campaign) { Factory(:campaign, :script => Factory(:script, :robo_recordings => [recording])) }
  let(:recording) { Factory(:robo_recording, :file_file_name => 'foo.wav') }
  let(:call_attempt) { Factory(:call_attempt, :campaign => campaign, :voter => Factory(:voter)) }

  it "proceeds with the call if the call was answered" do
    post :callback, :call_attempt_id => call_attempt.id, :CallStatus => 'in-progress'
    response.body.should == recording.twilio_xml(call_attempt)
    call_attempt.reload.status.should == CallAttempt::Status::MAP['in-progress']
  end

  ['queued', 'busy', 'failed', 'no-answer', 'canceled',].each do |call_status|
    it "hangs up if the call has a status of #{call_status}" do
      post :callback, :call_attempt_id => call_attempt.id, :CallStatus => call_status
      call_attempt.voter.reload.status.should == Voter::MAP[call_status]
      response.body.should == Twilio::Verb.hangup
      call_attempt.reload.status.should == CallAttempt::Status::MAP[call_status]
    end

    ['report_error', 'call_ended'].each do |callback|
      it "#{callback} updates the call attempt status on #{call_status}" do
        post callback, :call_attempt_id => call_attempt.id, :CallStatus => call_status
        call_attempt.reload.status.should == CallAttempt::Status::MAP[call_status]
      end
    end
  end

  it "hangs up a call that has reported an error" do
    post :report_error, :call_attempt_id => call_attempt.id, :CallStatus => CallAttempt::Status::INPROGRESS
    response.body.should == Twilio::Verb.hangup
  end

  it "plays a recorded message for a call answered by a machine" do
    recorded_message = Factory(:recording)
    campaign.update_attributes(:answering_machine_detect => true, :use_recordings => true, :recording => recorded_message)
    post :callback, :call_attempt_id => call_attempt.id, :CallStatus => 'in-progress', :AnsweredBy => 'machine'
    response.body.should == call_attempt.play_recorded_message
  end

end
