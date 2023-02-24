class UrlHelper
  include Singleton
  include Rails.application.routes.url_helpers
end
