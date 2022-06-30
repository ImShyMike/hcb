# frozen_string_literal: true

class DocsController < ActionController::Base
  skip_before_action :verify_authenticity_token

  include Swagger::Blocks

  swagger_component do
    security_scheme :ApiKeyAuth do
      key :type, :apiKey
      key :in, :header
      key :name, :Authorization
    end
  end

  swagger_root do
    key :openapi, "3.0.0"
    info do
      key :version, "2.0.0"
      key :title, "bank-api"
      key :description, "🏛 Process payments on Bank via an API"
    end

    security do
      key :ApiKeyAuth, []
    end
  end

  SWAGGERED_CLASSES = [
    ApplicationDocumentation,
    V2PartneredSignupsDocumentation,
    V2DonationsDocumentation,
    V2OrganizationsDocumentation,
    self
  ].freeze

  def swagger
    render json: Swagger::Blocks.build_root_json(SWAGGERED_CLASSES)
  end

end
