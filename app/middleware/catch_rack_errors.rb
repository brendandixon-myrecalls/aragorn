module Aragorn
  class CatchRackErrors
    def initialize(app)
      @app = app
    end

    def call(env)
      begin
        @app.call(env)
      rescue ActionDispatch::Http::Parameters::ParseError => error
        message = "Submitted JSON failed to parse: #{error}"
        return [
          400, { "Content-Type" => "application/vnd.api+json" },
          [ { errors: [ { status: 400, title: 'Bad Request', detail: message } ] }.to_json ]
        ]
      end
    end
  end
end
