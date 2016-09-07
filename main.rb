#!/usr/bin/env ruby

require 'zlib'
require 'nokogiri'
require 'active_support/inflector'

class Array
  def diff cmp_ary, recursive = true
    return [] if self == cmp_ary
    return cmp_ary if (cmp_ary.class != Array or self == [])

    r_array = []
    self.each_with_index do | value, key |
      if cmp_ary[key] != value
        if recursive and (value.class == Hash or value.class == Array) and value.class == cmp_ary[key].class
          r_array[key] = value.diff cmp_ary[key], recursive
        else
          r_array[key] = cmp_ary[key]
        end
      end
    end
    (cmp_ary - self).each do | value |
      r_array << value
    end
    r_array
  end
end

class Hash
  def diff cmp_ha, recursive = true
    return {} if self == cmp_ha
    return cmp_ha if (cmp_ha.class != Hash or self == {})

    r_hash = {}
    self.each do | key, value |
      if cmp_ha[key] != value and cmp_ha[key]
        if recursive and (value.class == Hash or value.class == Array) and value.class == cmp_ha[key].class
          r_hash[key] = value.diff cmp_ha[key], recursive
        else
          r_hash[key] = cmp_ha[key]
        end
      end
    end
    (cmp_ha.keys - self.keys).each do | key |
      r_hash[key] = cmp_ha[key]
    end
    r_hash
  end
end

module Nokogiri
  module XML
    class Node
      alias :all_children_to_array :children

      def children filter = nil
        if filter
          NodeSet.new self.document, self.all_children_to_array.filter(filter)
        else
          self.all_children_to_array
        end
      end
    end
  end
end

def read_dia_file file
  tables = []

  gz = Zlib::GzipReader.new(file)
  doc = Nokogiri::XML(gz) do | config |
    config.options = Nokogiri::XML::ParseOptions::NOBLANKS | Nokogiri::XML::ParseOptions::STRICT | Nokogiri::XML::ParseOptions::NONET
  end

  doc.remove_namespaces!
  doc.xpath('//layer').each do | layer |
    @out.puts "layer: #{layer["name"]}" if @options[:verbose]
    layer.children('object').each do | object |
      @out.puts "#{object["id"]} - #{object["type"]}" if @options[:verbose]
      table = {
        id: object["id"],
        type: object["type"]["Database - ".length..-1].downcase.intern
      }
      if table[:type] == :table
        name = object.children("attribute[@name='name']").first
        if name
          table[:name] = name.children.first.children.first.to_s[1..-2].downcase
        end
        attributes = object.children("attribute[@name='attributes']").first
        table[:fields] = fields = []
        if attributes
          attributes.children.each do | composite |
            field_name = composite.children("attribute[@name='name']").first
            type = composite.children("attribute[@name='type']").first
            field = Hash.new
            if field_name
              field[:name] = field_name.children.first.children.first.to_s[1..-2]
            end
            if type
              field[:type] = type.children.first.children.first.to_s[1..-2]
            end
            fields << field
          end
        end
      elsif table[:type] == :reference
        table[:connections] = connections = []
        connections_parent = object.children('connections').first
        if connections_parent
          connections_parent.children.each do | connection |
            connections << connection["to"]
          end
        end
      end

      tables << table
    end
  end
  tables.sort{|x, y|x[1..-1].to_i <=> y[1..-1].to_i}
end

if __FILE__ == $0

  require 'optparse'

  @out = $stdout

  @options = {}
  OptionParser.new do | opts |
    opts.banner = "Usage: main.rb [-v] [-i] [-p] [-o]"

    opts.on("-v", "--[no-]verbose", "Run verbosely") do | v |
      @options[:verbose] = v
    end
    opts.on("-pPREVIOUS", "--previous-state=PREVIOUS", "Previous state") do | ps |
      @options[:previousstate] = ps
    end
    opts.on("-o", "--output", "Output") do | o |
      @options[:output] = o
      @out = File.open @options[:output], "a"
    end
  end.parse!

  puts "Current:" if @options[:verbose]
  @tables = read_dia_file ARGF
  puts "Previous:" if @options[:verbose]
  @previouses = read_dia_file File.open @options[:previousstate] if @options[:previousstate]

  # p @previous
  # p @tables
  @previouses.each_with_index do | previous, i |
    # p previous
    # p @tables[i]
    p previous.diff @tables[i]
  end

  @out.puts if @options[:verbose]
  @out.puts "Tables:" if @options[:verbose]
  @name = "Create"
  @tables.each do | table |
    if table[:name]
      @name << table[:name].capitalize
    end
  end
  puts "class #{@name} < ActiveRecord::Migration"
  puts "  def change"
  @tables.select{|t|t[:type]==:table}.each do | table |
  puts "    create_table :#{table[:name].pluralize} do |t|"
  puts
  puts "      t.timestamps null: false"
    @tables.select{|t|t[:type]==:reference&&t[:connections][1]==table[:id]}.each do | reference |
      depend = @tables.select{|t|t[:id]==reference[:connections][0]}.first[:name]
  puts "      t.reference :#{depend}, null: true, foreign_key: true, type: :uuid"
    end
    table[:fields].each do | field |
  puts "      t.#{field[:type]} :#{field[:name]}"
    end
  puts "    end"
  end
  puts "  end"
  puts "end"

end
