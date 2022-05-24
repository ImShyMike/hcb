# frozen_string_literal: true

class OrganizerPositionInvitesMailerPreview < ActionMailer::Preview
  def notify
    @invite = OrganizerPositionInvite.last
    OrganizerPositionInvitesMailer.with(invite: @invite).notify
  end

end
