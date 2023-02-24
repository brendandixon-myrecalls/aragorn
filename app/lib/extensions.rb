class String

  def dejsonize
    self.underscore
  end

  def jsonize
    self.camelcase(:lower)
  end

end

class Symbol

  def dejsonize
    self.to_s.dejsonize.to_sym
  end

  def jsonize
    self.to_s.jsonize.to_sym
  end

end
