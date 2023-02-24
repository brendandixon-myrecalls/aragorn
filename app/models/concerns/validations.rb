module Validations
  extend ActiveSupport::Concern

  included do
    extend  HelperMethods
    include HelperMethods
  end

  module HelperMethods
    private
      def _merge_attributes(attr_names)
        options = attr_names.extract_options!.symbolize_keys
        attr_names.flatten!
        options[:attributes] = attr_names
        options
      end
  end

end

Dir[File.expand_path("../validators/*.rb", __dir__)].each do |file|
  if Rails.env.production?
    require file
  else
    load file
  end
end
