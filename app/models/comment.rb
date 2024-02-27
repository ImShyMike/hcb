# frozen_string_literal: true

# == Schema Information
#
# Table name: comments
#
#  id                 :bigint           not null, primary key
#  admin_only         :boolean          default(FALSE), not null
#  commentable_type   :string
#  content_ciphertext :text
#  has_untracked_edit :boolean          default(FALSE), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  commentable_id     :bigint
#  user_id            :bigint
#
# Indexes
#
#  index_comments_on_commentable_id_and_commentable_type  (commentable_id,commentable_type)
#  index_comments_on_commentable_type_and_commentable_id  (commentable_type,commentable_id)
#  index_comments_on_user_id                              (user_id)
#
class Comment < ApplicationRecord
  include Hashid::Rails
  include PublicIdentifiable

  set_public_id_prefix :cmt

  belongs_to :commentable, polymorphic: true
  belongs_to :user

  has_one_attached :file

  has_paper_trail skip: [:content] # ciphertext columns will still be tracked
  has_encrypted :content

  validates :user, presence: true
  validates :content, presence: true, unless: :has_attached_file?

  validate :commentable_includes_concern

  scope :admin_only, -> { where(admin_only: true) }
  scope :not_admin_only, -> { where(admin_only: false) }
  scope :edited, -> { joins(:versions).where("has_untracked_edit IS TRUE OR versions.event = 'update' OR versions.event = 'destroy'") }
  scope :has_attached_file, -> { joins(:file_attachment) }

  def edited?
    has_untracked_edit? or
      versions.where("event = 'update' OR event = 'destroy'").any?
  end

  def has_attached_file?
    file.attached?
  end

  private

  def commentable_includes_concern
    unless commentable.class.included_modules.include?(Commentable)
      errors.add(:commentable_type, "is not commentable")
    end
  end

end
