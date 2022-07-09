# frozen_string_literal: true

module Api
  module Entities
    class LinkedObjectBase < Base
      API_LINKED_OBJECT_TYPE = "linked_objects"

      when_expanded do
        expose :memo do |obj, options|
          obj.local_hcb_code.memo
        end
      end

      expose_associated Transaction, hide: [API_LINKED_OBJECT_TYPE, Organization] do |obj, options|
        # Don't show the Organizations for these association Transactions since
        # they will belong to the same Organization as the one associated below
        # (in this Linked Object)

        obj.local_hcb_code
      end

      expose_associated Organization, hide: [API_LINKED_OBJECT_TYPE, Transaction] do |obj, options|
        obj.event
      end

    end
  end
end
