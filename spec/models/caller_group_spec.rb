require 'rails_helper'

describe CallerGroup, :type => :model do
  context 'validations' do
    it {is_expected.to validate_presence_of :name}
    it {is_expected.to have_many :callers}
    it {is_expected.to belong_to :campaign}
    it {is_expected.to belong_to :account}
  end

  context 'campaign reassignment' do
    let(:account){ create(:account) }
    let(:original_campaign){ create(:preview, account: account) }
    let(:caller_group){ create(:caller_group, campaign: original_campaign) }
    let(:caller){ create(:caller, campaign: original_campaign, caller_group: caller_group, account: account) }
    let(:new_campaign){ create(:predictive, account: account) }

    before do
      Redis.new.flushall
      caller_group.update_attributes(campaign_id: new_campaign.id)
    end

    after do
      Redis.new.flushall
    end

    it 'queues CallerGroupJob when new campaign saved' do
      expect(caller_group.campaign).to eq(new_campaign)
      expect(resque_jobs(:dial_queue)).to include({
        'class' => 'CallerGroupJob',
        'args' => [caller_group.id]
      })
    end

    it 'updates all associated callers to the new campaign' do
      expect(caller_group.campaign).to eq new_campaign
      caller_group.reassign_in_background
      expect(caller.campaign).to eq new_campaign
    end
  end
end

# ## Schema Information
#
# Table name: `caller_groups`
#
# ### Columns
#
# Name               | Type               | Attributes
# ------------------ | ------------------ | ---------------------------
# **`id`**           | `integer`          | `not null, primary key`
# **`name`**         | `string(255)`      | `not null`
# **`campaign_id`**  | `integer`          | `not null`
# **`created_at`**   | `datetime`         | `not null`
# **`updated_at`**   | `datetime`         | `not null`
# **`account_id`**   | `integer`          | `not null`
#
