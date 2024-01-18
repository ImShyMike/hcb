# frozen_string_literal: true

class OrganizerPositionPolicy < ApplicationPolicy
  def destroy?
    user.admin?
  end

  def set_index?
    record.user == user
  end

  def mark_visited?
    record.user == user
  end

  def toggle_signee_status?
    user.admin?
  end

end
