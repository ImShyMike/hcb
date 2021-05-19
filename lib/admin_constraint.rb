# Used to restrict access of Sidekiq to admins. See routes.rbfor more info.
class AdminConstraint
  include Rails.application.routes.url_helpers

  def matches?(request)
    token = request.cookie_jar['session_token']
    return false unless token.present?

    digest = User.digest(token)

    user = User.find_by(session_token: digest)
    user && user.admin?
  rescue BankApiService::UnauthorizedError
    false # user is not logged in
  end
end
