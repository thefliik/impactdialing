require "spec_helper"

describe VoterList do
  include ActionController::TestProcess

  it "can return all voter lists of the given ids" do
    v = 3.times.map { Factory(:voter_list) }
    VoterList.by_ids([v.first.id, v.last.id]).should == [v.first, v.last]
  end

  describe "enable and disable voter lists" do
    let(:campaign) { Factory(:campaign) }
    it "can disable all voter lists in the given scope" do
      Factory(:voter_list, :campaign => campaign, :enabled => true)
      Factory(:voter_list, :campaign => campaign, :enabled => true)
      Factory(:voter_list, :campaign => Factory(:campaign), :enabled => true)
      campaign.voter_lists.disable_all
      VoterList.all.map(&:enabled).should == [false, false, true]
    end
    it "can enable all voter lists in the given scope" do
      Factory(:voter_list, :campaign => campaign, :enabled => false)
      Factory(:voter_list, :campaign => campaign, :enabled => false)
      Factory(:voter_list, :campaign => Factory(:campaign), :enabled => false)
      campaign.voter_lists.enable_all
      VoterList.all.map(&:enabled).should == [true, true, false]
    end
  end

  describe "upload voters list" do
    let(:csv_file_upload) {
      fixture_path  = ActionController::TestCase.fixture_path
      source_file   = "#{fixture_path}files/valid_voters_list.csv"
      temp_dir      = "#{fixture_path}test_tmp"
      temp_filename = "#{temp_dir}/valid_voters_list.csv"
      FileUtils.cp source_file, temp_filename
      temp_filename
    }
    let(:user) { Factory(:user) }
    let(:campaign) { Factory(:campaign, :user => user) }
    let(:voter_list) { Factory(:voter_list, :campaign => campaign, :user_id => user.id) }

    describe "import from csv" do
      USER_MAPPINGS = CsvMapping.new({
          "LAST"      => "LastName",
          "FIRSTName" => "FirstName",
          "Phone"     => "Phone",
          "Email"     => "Email",
          "ID"        => "ID",
          "Age"       => "Age",
          "Gender"    => "Gender",
      })
      before :each do
        Voter.destroy_all
        @result = voter_list.import_leads(
            USER_MAPPINGS,
            csv_file_upload,
            ",")
      end

      it "should be successful" do
        @result.should == {
            :successCount => 2,
            :failedCount  => 0
        }
      end

      it "should parse it and save to the voters list table" do
        Voter.count.should == 1

        voter = Voter.first
        voter.campaign_id.should == campaign.id
        voter.user_id.should == user.id
        voter.voter_list_id.should == voter_list.id

        # check some values from the csv fixture
        voter.Phone.should == "1234567895"
        voter.FirstName.should == "Foo"
        voter.CustomID.should == "987"
        voter.LastName.should == "Bar"
        voter.Email.should == "foo@bar.com"
        voter.MiddleName.should be_blank
        voter.Suffix.should be_blank
      end

      it "should add a family member when two voters in the same voters list have same phone number" do
        Family.count.should == 1
        Voter.first.num_family.should == 2

        family_member = Family.first
        family_member.campaign_id.should == campaign.id
        family_member.user_id.should == user.id
        family_member.voter_list_id.should == voter_list.id

        # check some values from the csv fixture
        family_member.Phone.should == "1234567895"
        family_member.FirstName.should == "Chocolate"
        family_member.LastName.should == "Bar"
        family_member.Email.should == "choco@bar.com"
        family_member.MiddleName.should be_blank
        family_member.Suffix.should be_blank
      end
      it "should ignore the same phone is repeated in another voters list for the same campaign" do
        another_voter_list = Factory(:voter_list, :campaign => campaign, :user_id => user.id)
        another_voter_list.import_leads(
            USER_MAPPINGS,
            csv_file_upload,
            ",").should ==
            {
                :successCount => 0,
                :failedCount  => 2
            }
      end
      it "should add even if the same phone is repeated in a different campaign" do
        another_voter_list = Factory(:voter_list,
                                     :campaign => Factory(:campaign, :user => user),
                                     :user_id  => user.id)
        another_voter_list.import_leads(
            USER_MAPPINGS,
            csv_file_upload,
            ",").should ==
            {
                :successCount => 2,
                :failedCount  => 0
            }
      end
    end
  end

  describe "dial" do
    let(:voter_list) { Factory(:voter_list, :campaign => Factory(:campaign, :calls_in_progress => true)) }
    it "dials all the voters who have not been dialed yet" do
      voter1 = Factory(:voter, :voter_list => voter_list, :campaign => voter_list.campaign)
      voter2 = Factory(:voter, :voter_list => voter_list, :campaign => voter_list.campaign)
      voter1.should_receive(:dial)
      voter2.should_receive(:dial)
      voters = mock
      voters.should_receive(:not_dialed).and_return(mock('voters', :randomly => [voter1, voter2]))
      voter_list.stub!(:voters).and_return(voters)
      voter_list.dial
    end

    it "gives the list of voters to be dialed" do
      voter1 = Factory(:voter, :voter_list => voter_list, :campaign => voter_list.campaign)
      voter2 = Factory(:voter, :voter_list => voter_list, :campaign => voter_list.campaign)
      Factory(:call_attempt, :campaign => voter_list.campaign, :voter => voter1)
      voter_list.voters.not_dialed.should == [voter2]
    end

    it "gives the count of remaining voters" do
      voter_list = Factory(:voter_list)
      Factory(:voter, :voter_list => voter_list)
      attempted_voter = Factory(:voter, :voter_list => voter_list)
      callback_voter = Factory(:voter, :voter_list => voter_list, :call_back => true)
      Factory(:call_attempt, :voter => callback_voter)
      Factory(:call_attempt, :voter => attempted_voter)
      voter_list.voters_remaining.should == 2
    end
  end
end
