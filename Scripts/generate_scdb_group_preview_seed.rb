#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

mode = ARGV[0]
set = ARGV[1]
html_path = ARGV[2]
out_path = ARGV[3]

abort "Usage: ruby generate_scdb_group_preview_seed.rb <group|subset> <set> <html_path> <out_path>" unless %w[group subset].include?(mode) && set && html_path && out_path

html = File.read(html_path)
set_key = set.downcase

def extract_attrs(raw_attrs)
  raw_attrs.scan(/data-([a-z]+)="([^"]+)"/).to_h
end

def slugify(text)
  text.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/^_+|_+$/, '')
end

def normalized_group_title(set, title)
  trimmed = title.strip
  case set.upcase
  when 'ZBLL'
    trimmed.sub(/^ZBLL\s+/, '')
  when 'VLS'
    trimmed.sub(/^VLS\s+/, '')
  else
    trimmed
  end
end

entries = []

if mode == 'group'
  html.scan(/<a\s+data-search='[^']*'\s+href='a\/3x3\/[^']+'\s+class='search-category'[^>]*><div class="search-category-image"[^>]*><div class="(jcube|icube)"([^>]*)><\/div><\/div><div class="card-body mt-2">([^<]+)<\/div><\/a>/m) do |kind, raw_attrs, raw_title|
    attrs = extract_attrs(raw_attrs)
    title = normalized_group_title(set, raw_title)
    stickers = {}

    if kind == 'icube'
      next unless attrs['fl']
      stickers['fl'] = attrs['fl']
    else
      %w[us ub uf ul ur].each do |key|
        stickers[key] = attrs[key] if attrs[key]
      end
      next unless stickers.length == 5
    end

    entries << {
      'imageKey' => "#{set_key}_group_#{slugify(title)}",
      'stickers' => stickers
    }
  end
else
  html.scan(/<div class="jcube\s+set-image[^"]*"([^>]*)><div class="tree-progress">[^<]*<\/div><\/div>\s*<div>([^<]+)<\/div>/m) do |raw_attrs, raw_title|
    attrs = extract_attrs(raw_attrs)
    next unless %w[us ub uf ul ur].all? { |key| attrs[key] }

    entries << {
      'imageKey' => "#{set_key}_subset_#{slugify(raw_title.strip)}",
      'stickers' => {
        'us' => attrs['us'],
        'ub' => attrs['ub'],
        'uf' => attrs['uf'],
        'ul' => attrs['ul'],
        'ur' => attrs['ur']
      }
    }
  end
end

unique = {}
entries.each { |entry| unique[entry['imageKey']] ||= entry }

File.write(out_path, JSON.pretty_generate({ 'cases' => unique.values }))
