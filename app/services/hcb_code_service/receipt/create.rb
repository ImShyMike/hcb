# frozen_string_literal: true

module HcbCodeService
  module Receipt
    class Create
      def initialize(hcb_code_id:,
                     file:,
                     upload_method: nil,
                     current_user: nil)
        @hcb_code_id = hcb_code_id
        @file = file
        @upload_method = upload_method
        @current_user = current_user
      end

      def run
        hcb_code.update_column(:marked_no_or_lost_receipt_at, nil)
        hcb_code.receipts.create!(attrs)
      end

      private

      def attrs
        {
          file: @file,
          upload_method: @upload_method,
          user: @current_user
        }.compact
      end

      def hcb_code
        @hcb_code ||= HcbCode.find(@hcb_code_id)
      end

    end
  end
end
