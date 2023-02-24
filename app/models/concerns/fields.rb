module Fields
  extend ActiveSupport::Concern

  included do
    class_attribute :_fields
    class_attribute :_array_attributes
    class_attribute :_inbound_attributes
    class_attribute :_outbound_attributes
    class_attribute :_synthetic_attributes
    class_attribute :_json_attributes
    class_attribute :_meta_attributes

    class_attribute :_singular
    self._singular = self.name.underscore.jsonize.to_sym

    class_attribute :_plural
    self._plural = self.name.tableize.jsonize.to_sym

    class_attribute :_path
    self._path = self.name.tableize.to_sym
  end

  module ClassMethods

    def define_path(**options)
      if options[:path].present?
        self._path = options[:path]
      elsif options[:singleton]
        self._path = self._singular
      end
    end

    def path_for
      self._path
    end

    def define_fields(fields)
      self._fields = fields
      self._array_attributes = []
      self._inbound_attributes = []
      self._outbound_attributes = []
      self._synthetic_attributes = []
      self._json_attributes = []
      self._meta_attributes = []

      fields.each do |f|
        next unless f[:field].present?
        options = {
          type: f[:type]
        }
        options[:as] = f[:as] if f[:as].present?
        f[:permit] ||= [] if f[:type] == Array
        json_name = f[:as] || f[:field]
        jsonized_name = f[:type] == Array ? { json_name.jsonize => f[:permit] } : json_name.jsonize
        self._array_attributes << f[:field] if f[:type] == Array
        self._inbound_attributes << jsonized_name if f[:inbound]
        self._outbound_attributes << jsonized_name if f[:outbound]
        self._synthetic_attributes << jsonized_name if f[:synthetic]
        self._json_attributes << jsonized_name unless f[:internal] || f[:meta]
        self._meta_attributes << json_name if f[:meta]
        options[:default] = f[:default] if f.has_key?(:default)
        self.field f[:field], options unless !self.respond_to?(:field) || f[:inbound] || f[:synthetic]
      end

      fields.each do |f|
        next unless f[:embeds_one].present? || f[:embeds_many].present?
        json_name = f[:embeds_one] || f[:embeds_many]
        jsonized_name = json_name.jsonize
        attributes = { jsonized_name => json_name.to_s.classify.constantize._json_attributes }
        self._outbound_attributes << attributes if f[:outbound]
        self._json_attributes << attributes
        if f[:embeds_one].present?
          self.embeds_one json_name, **f.reject{|k, v| [:embeds_one, :outbound].include?(k) }
        else
          self.embeds_many json_name, **f.reject{|k, v| [:embeds_many, :outbound].include?(k) }
        end
        self.accepts_nested_attributes_for(json_name) unless f[:outbound]
      end

      # Note:
      # - Mongodb will automatically insert a BSON::ObjectId; this code relies, instead on it
      #   being explicitly declared so the correct JSON is both generated and accepted
      if self.respond_to?(:before_create)
        self.before_create :ensure_id
        self.before_save :ensure_id
        self.before_update :ensure_id
      end
    end

    # Convert an array of objects to JSON
    def as_json_collection(objects=[], **options)
      options[:limit] ||= 20
      options[:offset] ||= 0
      options[:total] ||= objects.length

      je = JsonEnvelope.new(self)

      if objects.present?
        parent = objects.first.embed_parent
        je.add_parent(parent) if parent.present?

        objects.each do |o|
          je.add_datum(o._id.present? ? o._id.to_s : nil, o.attributes_to_json)
        end

        je.add_related(Array(options[:related]).map{|o| o.as_json[:data]}) if options[:related].present?
      end

      je.add_pagination(options)

      je.as_json(collection: true)
    end

    # Extract the attributes from incoming parameters
    def attributes_from_params(params)
      o = params[self._singular] || {}
      o = o[:data] || {}
      o = [o] unless o.is_a?(Array)
      o = o.first || {}
      attributes_from_json(o[:attributes] || {})
    end

    # Convert incoming JSON to one or more target objects
    def from_json(j, **options)
      j = JSON.parse(j) if j.is_a?(String)
      je = JsonEnvelope.from_json(self._plural, j[self._singular] || j[self._plural] || j)

      objects = []
      je.each_datum do |id, attributes|
        attributes = attributes_from_json(attributes || {}, **options)
        o = self.new unless id.present?
        o ||= self.find(id) rescue self.new
        o.id = id if options[:all_fields] && id.present?
        o.attributes = attributes
        objects << o
      end

      # Return one object if the incoming JSON was not a collection
      (j[self._plural] || je.is_collection?) ? objects : objects.first
    end

    def inbound_attributes(disallowed_attributes = [])
      # Ignore the nested JSON-API id and type fields
      # - Accept only known attributes
      # - Accept ID as a top-level parameter
      # - Accept the object under the singular or plural names (e.g., recall or recalls)
      attributes = self._json_attributes
      attributes -= self._outbound_attributes
      attributes -= self._synthetic_attributes
      attributes -= (disallowed_attributes || [])
      attributes
    end

    def json_params_for(params, disallowed_attributes = [])
      single = { data: [{ attributes: self.inbound_attributes(disallowed_attributes) }] }
      params.permit(
        :id,
        self._singular => single,
        self._plural => [single])
    end

    def attributes_from_json(j, **options)
      h = {}
      self._fields.each do |f|
        if !options[:all_fields] && (f[:field] == :_id || f[:internal] || f[:synthetic] || f[:outbound])
          next
        elsif f[:field].present?
          json_name = (f[:as] || f[:field]).jsonize
          next unless j.has_key?(json_name)
          h[f[:as] || f[:field]] = j[json_name].is_a?(Array) ? j[json_name].reject{|v| v.blank?} : j[json_name]
        elsif f[:embeds_one].present? || f[:embeds_many].present?
          json_name = (f[:embeds_one] || f[:embeds_many]).jsonize
          next unless j.has_key?(json_name)
          klass = json_name.to_s.classify.constantize
          h["#{json_name.dejsonize}_attributes".to_sym] = if f[:embeds_one].present?
              klass.attributes_from_json(j[json_name], **options)
            else
              j[json_name].map{|a| klass.attributes_from_json(a, **options)}
            end
        end
      end
      h.deep_symbolize_keys
    end

    def to_objectid(values)
      values = [values] unless values.is_a?(Array)
      values.map{|v| v.is_a?(String) ? BSON::ObjectId.from_string(v) : v}
      values.length <= 1 ? values.first : values
    end

  end

  def as_json(*args, **options)
    je = JsonEnvelope.new(self.class)

    parent = self.embed_parent
    je.add_parent(parent) if parent.present?

    je.add_datum(options[:skip_id] || self._id.blank? ? nil : self._id.to_s, self.attributes_to_json(**options))
    je.add_related(Array(options[:related]).map{|o| o.as_json[:data]}) if options[:related].present?
    self.class._meta_attributes.each do |f|
      je.add_meta(f, self.send(f))
    end

    je.as_json(*args, **options)
  end

  def attributes_to_json(**options)
    h = {}

    self.class._fields.each do |f|
      next if f[:field] == :_id
      next if f[:internal]
      next if f[:inbound]
      next if f[:meta]
      next if f[:embeds_one]
      next if f[:embeds_many]

      json_name = f[:as] || f[:field]
      next if (options[:exclude] || []).include?(json_name)

      v = self.send(f[:field])
      v = v.to_s(:json) if v.is_a?(DateTime) || v.is_a?(Time)
      v = v.to_s if v.is_a?(BSON::ObjectId)
      h[json_name.jsonize] = v
    end

    embedded_options = options.merge(flat: true, parent: self.embed_parent)
    self.associations.each do |k, v|
      if v.is_a?(Mongoid::Association::Embedded::EmbedsOne)
        h[v.name.jsonize] = self.send(v.name).as_json(**embedded_options.merge(skip_id: true))
      elsif v.is_a?(Mongoid::Association::Embedded::EmbedsMany)
        h[v.name.jsonize] = self.send(v.name).map{|a| a.as_json(**embedded_options)}
      end
    end if self.respond_to?(:associations)

    h.deep_symbolize_keys
  end

  def embed_parent
    return nil unless self.respond_to?(:_parent)
    ep = self
    while ep._parent.present? do ep = ep._parent end
    ep != self ? ep : nil
  end

  def merged_errors
    self.class._fields.each do |f|
      if f[:embeds_one].present? && self.errors.has_key?(f[:embeds_one])
        self.errors.delete(f[:embeds_one])
        self.merge_embedded_errors(f[:embeds_one], self.send(f[:embeds_one]).merged_errors)
      elsif f[:embeds_many].present? && self.errors.has_key?(f[:embeds_many])
        self.errors.delete(f[:embeds_many])
        self.send(f[:embeds_many]).each{|o| self.merge_embedded_errors(f[:embeds_many], o.merged_errors)}
      end
    end
    self.errors
  end

  def path_for
    self.class.path_for
  end

  def write_attribute(name, value)
    if self.class._array_attributes.include?(name.to_sym) && value.present?
      value = [value] if value.present? && !value.is_a?(Array)
      value = value.uniq if value.length > 1
    end
    super(name, value)
  end

  protected

    def ensure_id
      self.id ||= BSON::ObjectId.new if self.respond_to?(:id=)
    end

    def merge_embedded_errors(embedded, errors)
      errors.each do |attribute, msg|
        key = embedded.to_s.singularize
        key = "#{key}_#{attribute}" unless attribute == :base
        self.errors.add(key.to_sym, msg)
      end
    end

end
