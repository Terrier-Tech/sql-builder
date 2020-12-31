require "test_helper"

class SqlBuilderTest < Minitest::Test
  # String
  def test_where_syntax_string
    query = SqlBuilder.new
                      .select(%w(id display_name created_at))
                      .from('locations')
                      .where("name=? and location=?", "foo", "bar")
    sql = query.to_sql
    assert sql.downcase =~ /select\s+id, display_name, created_at from locations\s+where\s+\(name='foo' and location='bar'\)/
  end

  #Time
  def test_where_syntax_time
    query = SqlBuilder.new
                      .select(%w(id display_name created_at))
                      .from('locations')
                      .where("date=?", "12:12:12 01-02-2020")
    sql = query.to_sql
    assert sql.downcase =~ /select\s+id, display_name, created_at from locations\s+where\s+\(date='12:12:12 01-02-2020'\)/
  end

  # Array
  # ex: .where("status in ?", ['action', 'complete'])
  #   => "status in ('action', 'complete')"
  def test_where_syntax_array
    query = SqlBuilder.new
                      .select(%w(id display_name created_at))
                      .from('locations')
                      .where("name=? and state in ? id=?","terrier", ["foo","bar"], 1)
    sql = query.to_sql
    puts sql
    assert sql.downcase =~ /select\s+id, display_name, created_at from locations\s+where\s+\(name in \('foo','bar'\)\)/
  end

  # Number
  def test_where_syntax_number
    query = SqlBuilder.new
                      .select(%w(id display_name created_at))
                      .from('locations')
                      .where("id=?", 1234)
    sql = query.to_sql
    assert sql.downcase =~ /select\s+id, display_name, created_at from locations\s+where\s+\(id=1234\)/
  end
end