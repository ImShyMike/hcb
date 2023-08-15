# frozen_string_literal: true

class AchTransferPolicy < ApplicationPolicy
  def index?
    user&.admin?
  end

  def new?
    is_public || admin_or_user
  end

  def create?
    admin_or_user && !record.event.demo_mode && !record.event.outernet_guild?
  end

  def show?
    is_public || admin_or_user
  end

  def cancel?
    admin_or_user
  end

  def transfer_confirmation_letter?
    admin_or_user
  end

  def start_approval?
    user&.admin?
  end

  def approve?
    user&.admin?
  end

  def reject?
    user&.admin?
  end

  private

  def admin_or_user
    user&.admin? || record.event.users.include?(user)
  end

  def is_public
    record.event.is_public?
  end

end
