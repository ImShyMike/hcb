# frozen_string_literal: true

module ApiService
  module V2
    class DeliverWebhook
      VALID_WEBHOOK_TYPES = [
        ::PartneredSignupService::DeliverWebhook::TYPE,
      ].freeze

      # POST to `webhook_url`
      def initialize(type:, webhook_url:, data:, secret:)
        @type = type
        @webhook_url = webhook_url
        @data = data
        @secret = secret

        @timestamp = Time.now
      end

      def run
        raise ArgumentError, "invalid webhook type '#{@type}'" unless valid_webhook_type?

        # don't deliver webhook if URL is not present
        return if @webhook_url.blank?

        res = conn.post(@webhook_url) do |req|
          req.headers["HCB-Signature"] = signature_header
          req.body = body
        end

        raise ArgumentError, "Error delivering webhook. HTTP status: #{res.status}" unless res.success?

        res
      end

      private

      def conn
        @conn ||= begin
          Faraday.new(new_attrs) do |faraday|
            faraday.use FaradayMiddleware::FollowRedirects, limit: 10
          end
        end
      end

      def new_attrs
        {
          headers: { "Content-Type" => "application/json" }
        }
      end

      def body
        body_and_type = @data
        body_and_type["meta"] = { type: @type }

        body_and_type.to_json
      end

      # This signature uses Stripe's webhook verification system
      # https://stripe.com/docs/webhooks/signatures#verify-manually
      # https://github.com/stripe/stripe-ruby/issues/912
      # https://github.com/stripe/stripe-ruby/blob/master/lib/stripe/webhook.rb
      def signature
        @signature ||= Stripe::Webhook::Signature.compute_signature(@timestamp, body, @secret)
      end

      def signature_header
        Stripe::Webhook::Signature.generate_header(@timestamp, signature)
      end

      def valid_webhook_type?
        VALID_WEBHOOK_TYPES.include?(@type)
      end

    end
  end
end
