class RenameLoadCardRequestsToEmburseTransfer < ActiveRecord::Migration[6.0]
  def change
    rename_table :load_card_requests, :emburse_transfers

    rename_column :transactions, :load_card_request_id, :emburse_transfer_id
  end
end
