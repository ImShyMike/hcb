class GSuite < ApplicationRecord
  VALID_DOMAIN = /[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?\z/ix

  has_paper_trail

  include AASM

  has_one :application, class_name: 'GSuiteApplication', required: false
  has_many :accounts, class_name: 'GSuiteAccount'
  belongs_to :event
  has_many :comments, as: :commentable

  aasm do
    state :creating, initial: true
    state :configuring
    state :verifying
    state :verified

    event :mark_creating do
      transitions to: :creating
    end

    event :mark_configuring do
      transitions to: :configuring
    end

    event :mark_verifying do
      transitions from: :configuring, to: :verifying
    end

    event :mark_verified do
      transitions from: :verifying, to: :verified
    end
  end

  scope :needs_human_review, -> { where("aasm_state in (?)", ["creating", "verifying"]) }

  validates :domain, presence: true, uniqueness: { case_sensitive: false }, format: { with: VALID_DOMAIN }


  after_initialize :set_application

  before_validation :clean_up_verification_key

  def verified_on_google?
    @verified_on_google ||= ::Partners::Google::GSuite::Domain.new(domain: domain).run.verified # TODO: move to a background job checking every 5-15 minutes for the latest verified domains
  rescue => e
    Airbrake.notify(e)

    false
  end

  def verification_url
    "https://www.google.com/webmasters/verification/verification?siteUrl=http://#{domain}&priorities=vdns,vmeta,vfile,vanalytics"
  end

  def ou_name
    "##{event.id} #{event.name.to_s.gsub("+", "")}" # TODO: fix this brittleness. our ou's have been tied to Event.name but that has multiple issues - a user could change their event name, an event name might have non-permitted characters in it for an ou name. we should just use event.id. probably requires migration of all old ous
  end

  private

  def set_application
    self.application = GSuiteApplication.find_by(domain: domain) # DEPRECATED
  end

  def clean_up_verification_key
    self.verification_key = verification_key.gsub("google-site-verification=", "") if verification_key.present?
  end
end
