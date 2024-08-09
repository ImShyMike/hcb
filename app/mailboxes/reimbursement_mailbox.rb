# frozen_string_literal: true

class ReimbursementMailbox < ApplicationMailbox
  # mail --> Mail object, this actual email
  # inbound_email => ActionMailbox::InboundEmail record --> the active storage record

  include Pundit::Authorization
  include HasAttachments

  before_processing :set_attachments
  before_processing :set_user

  def process
    return bounce_missing_attachments unless @attachments
    return bounce_missing_user unless @user

    # All good, now let's create the receipts

    result = ::ReceiptService::Create.new(
      # `receiptable` is intentionally `nil` to send it to the Receipt Bin
      uploader: @user,
      attachments: @attachments,
      upload_method: "email_receipt_bin"
    ).run!

    return bounce_error if result.empty?

    Reimbursement::MailboxMailer.with(
      mail: inbound_email,
      reply_to: mail.to.first,
      receipts_count: result.size
    ).bounce_success.deliver_now
  end

  private

  def set_user
    @user = User.find_by(email: mail.from[0])
  end

  def bounce_missing_user
    bounce_with Reimbursement::MailboxMailer.with(mail: inbound_email).bounce_missing_user
  end

  def bounce_error
    bounce_with Reimbursement::MailboxMailer.with(
      mail: inbound_email,
      reply_to: mail.to.first
    ).bounce_error
  end

end
