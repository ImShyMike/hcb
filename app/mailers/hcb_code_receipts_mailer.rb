# frozen_string_literal: true

class HcbCodeReceiptsMailer < ApplicationMailer
  before_action { @inbound_mail = params[:mail] }
  before_action { @reply_to = params[:reply_to] }
  before_action { @to = params[:to] || @inbound_mail&.mail&.from&.first }

  default to: -> { @to },
          reply_to: -> { @reply_to },
          subject: -> { @inbound_mail&.mail&.subject },
          in_reply_to: -> { @inbound_mail&.message_id },
          references: -> { [@inbound_mail&.mail&.header&.[]("References")&.value, @inbound_mail&.message_id].compact.join(" ") }

  def bounce_missing_user
    mail subject: "Unknown email address"
  end

  def bounce_missing_hcb
    mail subject: "Unknown transaction"
  end

  def bounce_missing_attachment
    mail subject: "Missing attachment(s)"
  end

  def bounce_success
    @receipts_count = params[:receipts_count]
    @renamed_to = params[:renamed_to]
    mail subject: "Thank you for your #{"receipt".pluralize(@receipts_count)}!"
  end

  def bounce_error
    mail subject: "An unknown error occured"
  end

end
