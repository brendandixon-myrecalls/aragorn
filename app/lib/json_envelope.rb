class JsonEnvelope

  JSON_API_VERSION = '1.0'

  class<<self

    @@base_uri = AragornConfig.base_uri

    def from_json(resource, json)
      json = JSON.parse(json) if json.is_a?(String)
      json = json.to_h unless json.is_a?(Hash)
      self.new(resource, json.deep_symbolize_keys)
    end

    def from_related(json, **options)
      json = JSON.parse(json) if json.is_a?(String)
      json = [json] unless json.is_a?(Array)
      json.map do |j|
        j = j.deep_symbolize_keys
        j[:type].singularize.classify.constantize.from_json({ data: j }, **options)
      end
    end

    def as_error(status, title, detail = nil)
      je = self.new
      je.add_error(status, title, detail)
      je
    end

  end

  def initialize(resource= nil, **options)
    @resource = resource

    options = options.with_indifferent_access
    @data = (options[:data] || [])
    @data = [@data] unless @data.is_a?(Array)
    @related = options[:included]
    @errors = options[:errors] || []
    @pages = (options[:links] || {})
    @parent = options[:parent]
    @path = options[:path]
    @meta = (options[:meta] || {})
    self.add_meta(:total, options[:total]) if options.has_key?(:total)
  end

  def add_datum(id = nil, **attributes)
    @data << self.to_resource(id, **attributes)
  end

  def add_error(status, title, detail = nil)
    error = {
      status: status,
      title: title
    }
    error[:detail] = detail if detail.present?
    @errors << error
  end

  def add_related(related = nil)
    return if related.blank?
    related = [related] unless related.is_a?(Array)
    @related = Array(related)
  end

  def add_meta(key, value)
    @meta ||= {}
    @meta[key] = value
  end

  def add_pagination(params)
    limit = [params[:limit] || Constants::DEFAULT_PAGE_SIZE, Constants::DEFAULT_PAGE_SIZE].min
    offset = [params[:offset] || 0, 0].max
    total = [params[:total] || 0, 0].max
    params = params.reject{|k, v| [:total].include?(k.to_sym)}

    self.add_meta(:total, total)

    @pages = {}.with_indifferent_access
    @pages[:self] = build_uri(query: params.merge(offset: offset).to_query)
    unless @parent.present?
      @pages[:first] = build_uri(query: params.merge(offset: 0).to_query)
      @pages[:prev] = offset > 0 ? build_uri(query: params.merge(offset: [offset-limit, 0].max).to_query) : nil
      @pages[:next] = (offset+limit) < total ? build_uri(query: params.merge(offset: offset+limit).to_query) : nil
      @pages[:last] = build_uri(query: params.merge(offset: [total-limit,0].max).to_query)
    end
  end

  def add_parent(parent)
    @parent = parent
  end

  def each_datum(&block)
    @data.each do |datum|
      yield datum[:id], datum[:attributes], datum[:meta]
    end
  end

  def each_error(&block)
    @errors.each do |error|
      yield error[:status] || error[:code], error[:title], error[:detail]
    end
  end

  def is_collection?
    @data.length > 1
  end

  def as_json(*args, **options)
    if options[:flat]
      json = {}
      datum = @data.first || {}
      json[:id] = datum[:id] if datum[:id].present?
      json = json.merge(datum[:attributes])
    else
      json = {
        jsonapi: {
          version: JSON_API_VERSION
        }
      }

      if @errors.length > 0
        json[:errors] = @errors
      else
        if self.is_collection? || options[:collection]
          json[:meta] = @meta if @meta.present?
          json[:data] = @data
          json[:links] = @pages if @pages.present?
        else
          datum = @data.first || {}
          json[:data] = datum
          json[:data][:links] = {
            self: build_uri(id: datum[:id])
          } if (datum[:id].present? || @path.present?) && !options[:exclude_self_link]
          json[:data][:meta] = @meta if @meta.present?
        end

        if @related.present?
          json[:included] = @related
        end
      end
    end

    json
  end

  protected

    def build_uri(**options)
      path = @parent.present? ? "/#{@parent.class.path_for}/#{@parent.id}" : ''
      path += "/#{@resource.path_for}" unless @resource.nil?
      path += "/#{@path}" if @path.present?
      path += "/#{options[:id]}" if options[:id].present?

      URI::Generic.new(
        @@base_uri.scheme, nil,
        @@base_uri.host, @@base_uri.port,
        nil, path, nil, @parent.present? ? nil : options[:query], nil).to_s
    end

    def to_resource(id, **attributes)
      d = {
        type: @resource.path_for.to_s,
      }
      d[:id] = id if id.present?
      d[:attributes] = attributes
      d
    end

end
