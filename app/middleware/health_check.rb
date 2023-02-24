module Aragorn
  class HealthCheck
    HEALTH_ROUTE = /\A\/health\s*\z/

    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)
      if HEALTH_ROUTE =~ request.path
        begin
          # TODO: Consider a "deep" health check
          # check_database
          [200, { 'Content-Type' => 'text/plan'}, [ 'Passed']]
        rescue Exception => e
          [200, { 'Content-Type' => 'text/plan'}, [ 'Failed']]
        end
      else
        @app.call(env)
      end
    end

    protected

      def check_database
        raise Exception.new('Data appears invalid') unless Recall.includes_categories('food').count > 0
      end

  end
end
