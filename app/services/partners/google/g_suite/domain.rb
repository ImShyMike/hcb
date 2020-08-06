module Partners
  module Google
    module GSuite
      class Domain
        include Partners::Google::GSuite::Shared::DirectoryClient

        def initialize(domain:)
          @domain = domain
        end

        def run
          directory_client.get_domain(gsuite_customer_id, @domain)
        end
      end
    end
  end
end
