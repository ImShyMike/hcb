# frozen_string_literal: true

class User < ApplicationRecord
  has_paper_trail

  include Commentable
  extend FriendlyId

  include PgSearch::Model
  pg_search_scope :search_name, against: [:full_name, :email, :phone_number], using: { tsearch: { prefix: true, dictionary: "english" } }

  friendly_id :slug_candidates, use: :slugged
  scope :admin, -> { where.not(admin_at: nil) }
  scope :has_session_token, -> { where.not(session_token: nil) }

  has_many :login_tokens
  has_many :user_sessions, dependent: :destroy
  has_many :organizer_position_invites
  has_many :organizer_positions
  has_many :organizer_position_deletion_requests, inverse_of: :submitted_by
  has_many :organizer_position_deletion_requests, inverse_of: :closed_by
  has_many :webauthn_credentials

  has_many :events, through: :organizer_positions

  has_many :ops_checkins, inverse_of: :point_of_contact
  has_many :managed_events, inverse_of: :point_of_contact

  has_many :g_suite_accounts, inverse_of: :fulfilled_by
  has_many :g_suite_accounts, inverse_of: :creator

  has_many :emburse_transfers
  has_many :emburse_card_requests
  has_many :emburse_cards
  has_many :emburse_transactions, through: :emburse_cards

  has_one :stripe_cardholder
  has_many :stripe_cards, through: :stripe_cardholder
  has_many :stripe_authorizations, through: :stripe_cards
  has_many :receipts

  has_many :checks, inverse_of: :creator

  has_one_attached :profile_picture

  has_one :partner, inverse_of: :representative

  before_create :create_session_token
  before_create :format_number
  before_save :on_phone_number_update

  validate on: :update do
    if full_name.blank? && full_name_in_database.present?
      errors.add(:full_name, "can't be blank")
    end
  end

  validates :email, uniqueness: true, presence: true
  validates :phone_number, phone: { allow_blank: true }

  validate :profile_picture_format

  # admin? takes into account an admin user's preference
  # to pretend to be a non-admin, normal user
  def admin?
    self.admin_at.present? && !self.pretend_is_not_admin
  end

  # admin_override_pretend? ignores an admin user's
  # preference to pretend not to be an admin.
  def admin_override_pretend?
    self.admin_at.present?
  end

  def first_name
    @first_name ||= begin
                      return nil unless namae.given || namae.particle

                      (namae.given || namae.particle).split(" ").first
                    end
  end

  def last_name
    @last_name ||= begin
                     return nil unless namae.family

                     namae.family.split(" ").last
                   end
  end

  def initial_name
    @initial_name ||= if name.strip.split(" ").count == 1
                        name
                      else
                        "#{(first_name || last_name)[0..20]} #{(last_name || first_name)[0, 1]}"
                      end
  end

  def safe_name
    # stripe requires names to be 24 chars or less, and must include a last name
    return full_name unless full_name.length > 24

    initial_name
  end

  def name
    full_name || email_handle
  end

  def initials
    words = name.split(/[^[[:word:]]]+/)
    words.any? ? words.map(&:first).join.upcase : name
  end

  def pretty_phone_number
    Phonelib.parse(self.phone_number).national
  end

  def representative?
    self.partner.present?
  end

  def represented_partner
    self.partner
  end

  def beta_features_enabled?
    events.where(beta_features_enabled: true).any?
  end

  private

  def namae
    @namae ||= Namae.parse(name).first || Namae.parse(name_simplified).first || Namae::Name.new(given: name_simplified)
  end

  def name_simplified
    name.split(/[^[[:word:]]]+/).join(" ")
  end

  def email_handle
    @email_handle ||= email.split("@").first
  end

  def create_session_token
    self.session_token = SecureRandom.urlsafe_base64
  end

  def slug_candidates
    slug = normalize_friendly_id self.name
    # From https://github.com/norman/friendly_id/issues/480
    sequence = User.where("slug LIKE ?", "#{slug}-%").size + 2
    [slug, "#{slug} #{sequence}"]
  end

  def profile_picture_format
    return unless profile_picture.attached?
    return if profile_picture.blob.content_type.start_with? "image/"

    profile_picture.purge_later
    errors.add(:profile_picture, "needs to be an image")
  end

  def format_number
    self.phone_number = Phonelib.parse(self.phone_number).sanitized
  end

  def on_phone_number_update
    # if we previously have a phone number and the phone number is not null
    if phone_number_changed?
      # turn all this stuff off until they reverify
      self.phone_number_verified = false
      self.use_sms_auth = false
      # Update the Hackclub API as well
      Partners::HackclubApi::UpdateUser.new(api_access_token, phone_number: phone_number).run
    end
  end

end
