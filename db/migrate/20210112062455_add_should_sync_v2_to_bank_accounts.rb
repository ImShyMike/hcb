# frozen_string_literal: true

class AddShouldSyncV2ToBankAccounts < ActiveRecord::Migration[6.0]
  def change
    add_column :bank_accounts, :should_sync_v2, :boolean, default: false
  end

end
