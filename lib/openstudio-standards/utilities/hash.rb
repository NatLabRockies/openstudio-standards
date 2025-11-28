class Hash
  # Add a "dig" method to Hash to check if deeply nested elements exist
  # From: http://stackoverflow.com/questions/1820451/ruby-style-how-to-check-whether-a-nested-hash-element-exists
  def dig(*path)
    path.inject(self) do |location, key|
      location.respond_to?(:keys) ? location[key] : nil
    end
  end

  def deeply_symbolize_keys
    transform_keys(&:to_sym).transform_values do |value|
      value.is_a?(Hash) ? value.deeply_symbolize_keys : value
    end
  end
end
