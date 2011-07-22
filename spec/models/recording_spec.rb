require "spec_helper"

describe Recording do
  it { should validate_presence_of(:file_file_name).with_message(/File can't be blank/) }
  it { should validate_presence_of :name }

  ['mp3', 'aif', 'aiff', 'wav'].each do |extension|
    it "accepts files with an extension of #{extension}" do
      recording = Factory.build(:recording, :file_file_name => "foo.#{extension}")
      recording.should be_valid
    end
  end

  it "is not valid with a file of a different extension" do
    recording = Factory.build(:recording, :file_file_name => 'foo.swf')
    recording.should_not be_valid
    recording.errors.on(:base).should == "Filetype swf is not supported.  Please upload a file ending in .mp3, .wav, or .aiff"
  end
end
