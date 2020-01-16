class GSuiteAccountPolicy < ApplicationPolicy
  def index?
    user.admin?
  end

  def create?
    user.admin? || record.g_suite.event.users.include?(user)
  end

  def show?
    user.admin? || record.event.users.include?(user)
  end

  def reset_password?
    user.admin? || record.event.users.include?(user)
  end

  def edit?
    user.admin?
  end

  def update?
    user.admin?
  end

  def destroy?
    user.admin?
  end

  def reject?
    user.admin?
  end
end
