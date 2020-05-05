module SessionsHelper
  def sign_in(user)
    session_token = User.new_session_token
    cookies.permanent[:session_token] = session_token
    user.update_attribute(:session_token, User.digest(session_token))

    # probably a better place to do this, but we gotta assign any pending
    # organizer position invites - see that class for details
    OrganizerPositionInvite.pending_assign.where(email: user.email).find_each do |invite|
      invite.update(user: user)
    end

    self.current_user = user
  end

  def signed_in?
    !current_user.nil?
  end

  def admin_signed_in?
    signed_in? && current_user&.admin?
  end

  def current_user=(user)
    @current_user = user
  end

  def organizer_signed_in?
    (signed_in? && @event&.users&.include?(current_user)) || admin_signed_in?
  end

  def current_user(ensure_api_authorized = true)
    session_token = User.digest(cookies[:session_token])
    @current_user ||= User.find_by(session_token: session_token)
    return nil unless @current_user

    if ensure_api_authorized
      # ensure that our auth token is valid. this will throw
      # ApiService::UnauthorizedError if we get an authorization error, which
      # will be caught by ApplicationController and sign out the user
      Rails.cache.fetch("#{@current_user.cache_key_with_version}/authed", expires_in: 1.hour) do
        @current_user.api_record.present?
      end
    end

    @current_user
  end

  def signed_in_user
    unless signed_in?
      store_location
      redirect_to auth_users_path
    end
  end

  def signed_in_admin
    unless admin_signed_in?
      store_location
      redirect_to auth_users_path, flash: { error: 'You’ll need to sign in as an admin.' }
    end
  end

  def sign_out
    current_user(false).update_attribute(:session_token, User.digest(User.new_session_token))
    cookies.delete(:session_token)
    self.current_user = nil
  end

  def redirect_back_or(default)
    redirect_to(session[:return_to] || default)
    session.delete(:return_to)
  end

  def store_location
    session[:return_to] = request.url if request.get?
  end
end
