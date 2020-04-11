require_relative './query_row'

# wraps the result of a SQL query into a container of objects
# a new QueryResult will contain an array of objects implementing a
# custom class derived from QueryRow containing convenience methods to access values
class QueryResult

  attr_reader :columns

  def initialize(raw)
    @columns = []
    if raw.empty?
      @array = raw
    else
      @row_class = create_row_class raw.first
      @array = raw.map do |raw_row|
        @row_class.new self, raw_row
      end
    end
  end

  def each
    return @array.to_enum(:each) unless block_given?
    @array.each do |row|
      yield row
    end
  end

  def map
    return @array.to_enum(:map) unless block_given?
    @array.map do |row|
      yield row
    end
  end

  def select
    return @array.to_enum(:select) unless block_given?
    @array.select do |row|
      yield row
    end
  end

  def group_by
    return @array.to_enum(:group_by) unless block_given?
    @array.group_by do |row|
      yield row
    end
  end

  def sort_by
    self.to_a.sort_by
  end

  def to_a
    @array
  end

  def count
    @array.count
  end

  def length
    @array.count
  end

  def first
    @array.first
  end

  def column_names
    @columns.map{|c| c[:name]}
  end

  def as_json(options={})
    @array.map do |row|
      row.as_json options
    end
  end

  def to_csv
    return '' if @array.empty?
    CSV.generate do |csv|
      csv << column_names
      self.each do |row|
        csv << @columns.map{|col| row.serialize_value(col)}
      end
    end
  end

  # computes a new column by evaluating a block for every row
  def compute_column(name)
    return unless @row_class # empty result
    name_s = name.to_s
    define_column_method @row_class, name_s
    each do |row|
      new_val = yield row
      row.send "#{name}=", new_val
    end
  end

  # computes new columns by evaluating a block for every row
  # the block should return a hash of new column values
  def compute_columns
    return unless @row_class # empty result
    columns_defined = false
    each do |row|
      new_vals = yield row
      unless columns_defined
        columns_defined = true
        new_vals.each_key do |name|
          define_column_method @row_class, name.to_s
        end
      end
      new_vals.each do |key, val|
        row.send "#{key}=", val
      end
    end
  end

  def remove_column(name)
    @columns.delete_if {|c| c[:name] == name.to_s}
  end

  TRUE_STRINGS = %w(1 true t)

  def define_column_method(row_class, name)
    name_s = name.to_s
    type = QueryResult.column_type name_s
    @columns << {name: name_s, type: type}
    case type
    when :raw
      row_class.define_method name do
        self.instance_variable_get('@raw')[name_s]
      end
      row_class.define_method "#{name}=" do |val|
        self.instance_variable_get('@raw')[name_s] = val
      end
    when :array
      row_class.define_method name do
        val = self.instance_variable_get('@raw')[name_s]
        if val.is_a? String
          val.parse_postgres_array
        else
          val
        end
      end
      row_class.define_method "#{name}=" do |val|
        self.instance_variable_get('@raw')[name_s] = val
      end
    when :bool
      row_class.define_method name do
        raw = self.instance_variable_get('@raw')[name_s]
        TRUE_STRINGS.include?(raw.to_s.downcase)
      end
      row_class.define_method "#{name}=" do |val|
        self.instance_variable_get('@raw')[name_s] = TRUE_STRINGS.include?(val.to_s.downcase)
      end
    when :dollars
      row_class.define_method name do
        self.instance_variable_get('@raw')[name_s].to_i/100.0
      end
      row_class.define_method "#{name}=" do |val|
        self.instance_variable_get('@raw')[name_s] = ((val || 0)*100).to_i
      end
    when :time
      row_class.define_method name do
        raw_time = self.instance_variable_get('@raw')[name_s]
        case raw_time
        when String
          time = Time.parse(raw_time)
          self.instance_variable_get('@raw')[name_s] = time
          time
        else
          raw_time
        end
      end
      row_class.define_method "#{name}=" do |val|
        self.instance_variable_get('@raw')[name_s] = val
      end
    when :date
      row_class.define_method name do
        raw_date = self.instance_variable_get('@raw')[name_s]
        case raw_date
        when String
          date = Date.parse(raw_date)
          self.instance_variable_get('@raw')[name_s] = date
          date
        else
          raw_date
        end
      end
      row_class.define_method "#{name}=" do |val|
        self.instance_variable_get('@raw')[name_s] = val
      end
    when :integer
      row_class.define_method name do
        raw = self.instance_variable_get('@raw')[name_s]
        if raw.blank?
          nil
        elsif raw.is_a? Integer
          raw
        elsif raw =~ /^-*\d+$/
          i = raw.to_i
          self.instance_variable_get('@raw')[name_s] = i
          i
        else
          raw
        end
      end
      row_class.define_method "#{name}=" do |val|
        self.instance_variable_get('@raw')[name_s] = val.to_i
      end
    when :float
      row_class.define_method name do
        self.instance_variable_get('@raw')[name_s].to_f
      end
      row_class.define_method "#{name}=" do |val|
        self.instance_variable_get('@raw')[name_s] = val.to_f
      end
    when :json
      row_class.define_method name do
        JSON.parse self.instance_variable_get('@raw')[name_s]
      end
      row_class.define_method "#{name}=" do |val|
        self.instance_variable_get('@raw')[name_s] = val.as_json
      end
    when :geo
      row_class.define_method name do
        self.instance_variable_get('@raw')[name_s]&.parse_geo_point
      end
      row_class.define_method "#{name}=" do |val|
        self.instance_variable_get('@raw')[name_s] = val
      end
    else # string
      row_class.define_method name do
        self.instance_variable_get('@raw')[name_s]
      end
      row_class.define_method "#{name}=" do |val|
        self.instance_variable_get('@raw')[name_s] = val.to_s
      end
    end
  end


  private

  ARRAY_SUFFIXES = %w(_array tags ies recipients)
  BOOL_PREFIXES = %w(is_)
  RAW_SUFFIXES = %w(_items lanes certs)
  DOLLARS_SUFFIXES = %w(price dollars total tax _value amount balance)
  TIME_SUFFIXES = %w(_at time)
  DATE_SUFFIXES = %w(_date)
  INTEGER_EXACT = %w(x y value)
  INTEGER_SUFFIXES = %w(number count duration _i)
  INTEGER_PREFIXES = %w(days_since days_until)
  FLOAT_SUFFIXES = %w(_m _miles distance latitude longitude _score _f)
  JSON_SUFFIXES = %w(weather)
  GEO_SUFFIXES = %w(geo)

  def self.column_type(key)
    key_s = key.to_s
    if key_s == '_state'
      return :integer
    end
    RAW_SUFFIXES.each do |suffix|
      if key_s.ends_with?(suffix)
        return :raw
      end
    end
    ARRAY_SUFFIXES.each do |suffix|
      if key_s.ends_with?(suffix)
        return :array
      end
    end
    BOOL_PREFIXES.each do |suffix|
      if key_s.start_with?(suffix)
        return :bool
      end
    end
    DOLLARS_SUFFIXES.each do |suffix|
      if key_s.ends_with?(suffix)
        return :dollars
      end
    end
    TIME_SUFFIXES.each do |suffix|
      if key_s.ends_with?(suffix)
        return :time
      end
    end
    DATE_SUFFIXES.each do |suffix|
      if key_s.ends_with?(suffix)
        return :date
      end
    end
    if INTEGER_EXACT.index(key_s)
      return :integer
    end
    INTEGER_SUFFIXES.each do |suffix|
      if key_s.ends_with?(suffix)
        return :integer
      end
    end
    INTEGER_PREFIXES.each do |prefix|
      if key_s.start_with?(prefix)
        return :integer
      end
    end
    FLOAT_SUFFIXES.each do |suffix|
      if key_s.ends_with?(suffix)
        return :float
      end
    end
    GEO_SUFFIXES.each do |suffix|
      if key_s.ends_with?(suffix)
        return :geo
      end
    end
    JSON_SUFFIXES.each do |suffix|
      if key_s.ends_with?(suffix)
        return :json
      end
    end
    :string
  end

  def create_row_class(template)
    this = self
    Class.new QueryRow do
      template.each do |key, value|
        this.define_column_method self, key
      end
    end
  end

end
