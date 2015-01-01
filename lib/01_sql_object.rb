require_relative 'db_connection'
require 'active_support/inflector'
# NB: the attr_accessor we wrote in phase 0 is NOT used in the rest


class SQLObject
  def self.columns
    query = DBConnection.execute2(<<-SQL)
      SELECT * FROM #{table_name}
    SQL
    columns = query.first.map do |el|
      el.to_sym
    end

    columns
  end


  def self.finalize!
    columns.each do |name|
      define_method(name) do
        attributes[name]
      end

      define_method("#{name}=") do |set|
        attributes[name] = set
      end
    end
  end

  def self.table_name=(table_name)
    @table_name = table_name   #class instance variable

  end

  def self.table_name
    @table_name ||= "#{self.to_s.downcase}s"
  end

  def self.all
    results = DBConnection.execute(<<-SQL)
      SELECT #{table_name}.* FROM #{table_name}
    SQL
    self.parse_all(results)
  end

  def self.parse_all(results)     # can we do this as a map, not an each?
    object_array = []
    results.map { |attrs| object_array << self.new(attrs) }
    object_array
  end

  def self.find(id)
    object_array = DBConnection.execute(<<-SQL, id)
      SELECT #{table_name}.* FROM #{table_name} WHERE #{table_name}.id = ?
    SQL
    object_array.any? ? self.new(object_array.first) : nil
  end

  def initialize(params = {})
    params.each do |attr_name, value|
      attr_name = attr_name.to_sym
      unless self.class.columns.include?(attr_name)
        raise ArgumentError.new "unknown attribute '#{attr_name}'"
      end

      self.send("#{attr_name}=", value)
    end
  end

  def attributes
    @attributes ||= {}
  end

  def attribute_values
    attr_values = []
    self.class.columns.map do |column|
      attr_values << self.send(column.to_sym)
    end

    attr_values
  end

  def insert
    col_names = attributes.keys.join(", ")
    q_marks = (["?"] * attributes.keys.length).join(", ")

    DBConnection.execute(<<-SQL, *attribute_values.drop(1))
      INSERT INTO
        #{self.class.table_name} (#{col_names})
      VALUES
        (#{q_marks})
    SQL

    self.id = DBConnection.last_insert_row_id
  end

  def update
    col_names = attributes.keys.map { |key| "#{key} = ?" }.join(", ")

    DBConnection.execute(<<-SQL, *attribute_values)
      UPDATE
        #{self.class.table_name}
      SET
        #{col_names}
      WHERE
        id = #{self.id}
      SQL
  end

  def save
    self.id.nil? ? insert : update
  end
end
