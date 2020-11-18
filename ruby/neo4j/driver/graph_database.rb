# frozen_string_literal: true

module Neo4j::Driver
  class GraphDatabase
    class << self
      extend AutoClosable
      include Ext::ConfigConverter
      include Ext::ExceptionCheckable

      auto_closable :driver, :routing_driver

      def driver(uri, auth_token = nil, **config)
        check do
          uri = URI(uri)
          config = to_java_config(org.neo4j.driver.Config, config)

          Internal::DriverFactory.new_instance(
            uri,
            auth_token || org.neo4j.driver.AuthTokens.none,
            config.routing_settings,
            config.retry_settings,
            config,
            config.security_settings.create_security_plan(uri.scheme)
          )
        end
      end

      def routing_driver(routing_uris, auth_toke, **config)

        assert_routing_uris(routing_uris)
        log = create_logger(config)

        routing_uris.each do |uri|
          driver = driver(uri, auth_toke, **config)
          begin
            return driver.tap(&:verify_connectivity)
          rescue Exceptions::ServiceUnavailableException => e
            log.warn("Unable to create routing driver for URI: #{uri}", e)
            close_driver(driver, uri, log)
          rescue Exception => e
            close_driver(driver, uri, log)
            raise e
          end
        end

        raise Exceptions::ServiceUnavailableException, 'Failed to discover an available server'
      end

      private

      def close_driver(driver, uri, log)
        driver.close
      rescue StandardError => close_error
        log.warn("Unable to close driver towards URI: " + uri, close_error)
      end

      def assert_routing_uris(uris)
        uris.find { |uri| URI(uri).scheme != Internal::Scheme::NEO4J_URI_SCHEME }&.tap do |uri|
          raise ArgumentError,
                "Illegal URI scheme, expected '#{Internal::Scheme::NEO4J_URI_SCHEME}' in '#{uri}'"
        end
      end

      def create_logger(**config)
        to_java_config(org.neo4j.driver.Config, config).logging.get_log(name)
      end
    end
  end
end