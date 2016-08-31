#!/usr/bin/env ruby

if __FILE__ == $0

  require 'zlib'
  require 'nokogiri'
  require 'active_support/inflector'

  @tables = []

  Zlib::GzipReader.open('example/Diagram1.dia') do | gz |
    doc = Nokogiri::XML(gz) do | config |
      config.options = Nokogiri::XML::ParseOptions::NOBLANKS | Nokogiri::XML::ParseOptions::STRICT | Nokogiri::XML::ParseOptions::NONET
    end
    doc.remove_namespaces!
    doc.xpath('//layer').each do | layer |
      # puts "layer: #{layer["name"]}"
      layer.children.filter('object').each do | object |
        # puts "#{object["id"]} - #{object["type"]}"
        table = {
          id: object["id"],
          type: object["type"]["Database - ".length..-1].downcase.intern
        }
        if table[:type] == :table
          name = object.children.filter('attribute[@name=\'name\']').first
          if name
            table[:name] = name.children.first.children.first.to_s[1..-2].downcase
          end
          attributes = object.children.filter('attribute[@name=\'attributes\']').first
          table[:fields] = fields = []
          if attributes
            attributes.children.each do | composite |
              field_name = composite.children.filter('attribute[@name=\'name\']').first
              type = composite.children.filter('attribute[@name=\'type\']').first
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
          connections_parent = object.children.filter('connections').first
          if connections_parent
            connections_parent.children.each do | connection |
              connections << connection["to"]
            end
          end
        end

        @tables << table
      end
    end
  end
  @tables.sort{|x, y|x[1..-1].to_i <=> y[1..-1].to_i}

  # puts
  # puts "Tables:"
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
