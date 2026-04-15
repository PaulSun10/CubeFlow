#!/usr/bin/env ruby
# frozen_string_literal: true

require 'cgi'
require 'json'
require 'open3'
require 'set'
require 'shellwords'

SET_CONFIG = {
  'PLL' => { resource: 'pll', puzzle_path: '3x3' },
  'OLL' => { resource: 'oll', puzzle_path: '3x3' },
  'F2L' => { resource: 'f2l', puzzle_path: '3x3' },
  'AdvancedF2L' => { resource: 'advancedf2l', puzzle_path: '3x3' },
  'COLL' => { resource: 'coll', puzzle_path: '3x3' },
  'WV' => { resource: 'wv', puzzle_path: '3x3' },
  'SV' => { resource: 'sv', puzzle_path: '3x3' },
  'CLS' => { resource: 'cls', puzzle_path: '3x3' },
  'SBLS' => { resource: 'sbls', puzzle_path: '3x3' },
  'CMLL' => { resource: 'cmll', puzzle_path: '3x3' },
  '4a' => { resource: '4a', puzzle_path: '3x3', page: 'EO4A' },
  'VLS' => { resource: 'vls', puzzle_path: '3x3' },
  'OLLCP' => { resource: 'ollcp', puzzle_path: '3x3' },
  'ZBLL' => { resource: 'zbll', puzzle_path: '3x3' },
  '1LLL' => { resource: '1lll', puzzle_path: '3x3' },
  'AntiPLL' => { resource: 'antipll', puzzle_path: '3x3' }
}.freeze

PLL_NAMES = {
  'Aa' => 'Aa Perm', 'Ab' => 'Ab Perm', 'E' => 'E Perm', 'F' => 'F Perm',
  'Ga' => 'Ga Perm', 'Gb' => 'Gb Perm', 'Gc' => 'Gc Perm', 'Gd' => 'Gd Perm',
  'H' => 'H Perm', 'Ja' => 'Ja Perm', 'Jb' => 'Jb Perm', 'Na' => 'Na Perm',
  'Nb' => 'Nb Perm', 'Ra' => 'Ra Perm', 'Rb' => 'Rb Perm', 'T' => 'T Perm',
  'Ua' => 'Ua Perm', 'Ub' => 'Ub Perm', 'V' => 'V Perm', 'Y' => 'Y Perm',
  'Z' => 'Z Perm'
}.freeze

USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36'
SETUP_ONLY = ENV['SCDB_SETUP_ONLY'] == '1'


def clean_text(value)
  CGI.unescape_html(value.to_s.gsub(/<[^>]+>/m, ' ').gsub(/\s+/, ' ').strip)
end

def ordered_unique(values)
  seen = {}
  values.each_with_object([]) do |value, result|
    next if value.nil? || value.empty? || seen[value]
    seen[value] = true
    result << value
  end
end

def slugify(value)
  value.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
end

def fetch_url(url, cookie_path: nil, referer: nil, xhr: false, retries: 3)
  args = ['curl', '-sS', '-L', '--connect-timeout', '10', '--max-time', '25', '-A', USER_AGENT, '-H', 'Accept-Language: en-US,en;q=0.9']
  args += ['-b', cookie_path, '-c', cookie_path] if cookie_path
  args += ['-H', "Referer: #{referer}"] if referer

  if xhr
    args += [
      '-H', 'Accept: */*',
      '-H', 'Sec-Fetch-Dest: empty',
      '-H', 'Sec-Fetch-Mode: cors',
      '-H', 'Sec-Fetch-Site: same-origin',
      '-H', 'X-Requested-With: XMLHttpRequest'
    ]
  end

  args << url

  attempts = 0
  begin
    attempts += 1
    stdout, stderr, status = Open3.capture3(*args)
    warn stderr unless status.success? || stderr.to_s.strip.empty?
    raise "Failed to fetch #{url}" unless status.success?
    stdout
  rescue StandardError
    raise if attempts >= retries

    sleep(0.5 * attempts)
    retry
  end
end

def fetch_more_algorithms(display_name, set_name, d_values)
  return [] if d_values.empty?
  return [] if SETUP_ONLY
  referer = "https://www.speedcubedb.com/a/3x3/#{set_name}/#{CGI.escape(display_name)}"

  d_values.flat_map do |d|
    url = "https://www.speedcubedb.com/category.algs.php?algname=#{CGI.escape(display_name)}&d=#{d}&cat=#{CGI.escape(set_name)}"
    html = fetch_url(url, referer: referer, xhr: true)
    html.scan(/<div class=\"formatted-alg\">(.*?)<\/div>/m).flatten.map { |alg| clean_text(alg) }
  end
end

def merge_setup(existing_item, scraped_item)
  merged = existing_item.dup
  merged['setup'] = scraped_item['setup']

  existing_groups = existing_item['algorithmGroups']
  scraped_groups = scraped_item['algorithmGroups']

  if existing_groups && scraped_groups
    scraped_by_id = scraped_groups.each_with_object({}) { |group, map| map[group['id']] = group }
    merged['algorithmGroups'] = existing_groups.map do |group|
      scraped = scraped_by_id[group['id']]
      scraped ? group.merge('setup' => scraped['setup']) : group
    end
  end

  merged
end

def extract_setup(html)
  clean_text(html[/<div class="setup-case[^"]*"><div>setup:<\/div>(.*?)<\/div>/m, 1])
end

def parse_orientation_groups(block, display_name, category_name, algorithm_id_prefix:)
  labels_by_index = block.scan(/<a class='nav-link(?: active)?' data-ori='(\d+)' href='#'><div class='subcatname'>(.*?)<\/div><\/a>/m)
                         .to_h { |index, title| [index, clean_text(title)] }
  group_matches = block.scan(/<div data-ori='(\d+)'[^>]*><ul class='list-group'[^>]*>(.*?)<\/ul><\/div>/m)

  group_matches.map do |orientation_index, group_html|
    title = labels_by_index.fetch(orientation_index, "Orientation #{orientation_index}")
    setup = extract_setup(group_html)
    inline_algorithms = group_html.scan(/<div class="formatted-alg">(.*?)<\/div>/m)
                                  .flatten
                                  .map { |alg| clean_text(alg) }
    d_values = group_html.scan(/more-algs no-print' data-category='#{Regexp.escape(category_name)}' data-d='(\d+)' data-algname='#{Regexp.escape(display_name)}'/).flatten.uniq
    more_algorithms = fetch_more_algorithms(display_name, category_name, d_values)
    algorithms = ordered_unique([*inline_algorithms, *more_algorithms])
    next if algorithms.empty?

    group_id = slugify(title)
    {
      'id' => group_id,
      'title' => title,
      'setup' => setup,
      'algorithms' => algorithms.each_with_index.map do |notation, index|
        {
          'id' => "#{algorithm_id_prefix}-#{group_id}-#{index + 1}",
          'notation' => notation,
          'isPrimary' => index.zero?,
          'source' => 'SpeedCubeDB',
          'tags' => []
        }
      end
    }
  end.compact
end

def parse_stickers(block)
  if (fl = block[/data-fl="([^"]+)"/, 1])
    { 'fl' => fl.to_s }
  else
    sticker_data = {
      'us' => block[/data-us="([^"]+)"/, 1].to_s,
      'ub' => block[/data-ub="([^"]+)"/, 1].to_s,
      'uf' => block[/data-uf="([^"]+)"/, 1].to_s,
      'ul' => block[/data-ul="([^"]+)"/, 1].to_s,
      'ur' => block[/data-ur="([^"]+)"/, 1].to_s
    }
    sticker_data.values.any?(&:empty?) ? nil : sticker_data
  end
end

def extract_blocks(html)
  html.scan(/(<div class="row singlealgorithm g-0".*?)(?=<div class="row singlealgorithm g-0"|\z)/m).flatten
end

def extract_child_paths(html)
  html.scan(/<a [^>]*href=['"]((?:\/)?a\/3x3\/[^'"]+)['"][^>]*class=['"]search-category['"]/m)
      .flatten
      .uniq
      .map { |path| path.start_with?('/') ? path[1..] : path }
end

def extract_child_entries(html)
  html.scan(/<a [^>]*href=['"]((?:\/)?a\/3x3\/[^'"]+)['"][^>]*class=['"]search-category['"][^>]*>.*?<div class=["']card-body mt-2["']>(.*?)<\/div><\/a>/m)
      .map { |path, title| [(path.start_with?('/') ? path[1..] : path), clean_text(title)] }
end

def normalized_group_title(set_name, title)
  cleaned = clean_text(title)
  return cleaned if cleaned.empty?

  case set_name
  when 'VLS'
    cleaned.sub(/\AVLS\s+/, '')
  when 'ZBLL'
    cleaned.sub(/\AZBLL\s+/, '')
  else
    cleaned
  end
end

def group_title_from_path(set_name, path)
  slug = path.split('/').last.to_s

  case set_name
  when 'VLS'
    {
      'VLSUB' => 'UB',
      'VLSUBUL' => 'UB UL',
      'VLSUF' => 'UF',
      'VLSUFUB' => 'UF UB',
      'VLSUFUL' => 'UF UL',
      'VLSUL' => 'UL',
      'VLSNE' => 'No Edges'
    }[slug]
  when 'OLLCP'
    if (match = slug.match(/\AOLLCP(\d+)\z/))
      "OLLCP #{match[1].to_i}"
    end
  when 'ZBLL'
    if slug == 'ZBLLAS'
      'AS'
    elsif (match = slug.match(/\AZBLL(.+)\z/))
      match[1]
    end
  when '1LLL'
    case slug
    when 'PLL'
      'PLL'
    when 'AntiPLL'
      'Anti PLL'
    else
      if slug == 'ZBLLAS'
        'ZBLL AS'
      elsif (match = slug.match(/\AZBLL(.+)\z/))
        "ZBLL #{match[1]}"
      elsif (match = slug.match(/\A1LLL(\d+)\z/))
        "1LLL #{match[1].to_i}"
      end
    end
  end
end

def parse_block(block, fallback_category:, payload_resource:, top_set_name:, group_name:)
  display_name = block[/data-alg="([^"]+)"/, 1]&.strip
  subgroup = block[/data-subgroup="([^"]+)"/, 1].to_s.strip
  return nil if display_name.nil? || display_name.empty?

  normalized_group_name = group_name.to_s.strip
  base_slug = slugify(display_name)
  item_id =
    if top_set_name == '1LLL' && ['PLL', 'Anti PLL'].include?(normalized_group_name)
      "#{slugify(normalized_group_name)}_#{base_slug}"
    else
      base_slug
    end
  image_key =
    if top_set_name == '1LLL' && normalized_group_name == 'Anti PLL'
      "#{payload_resource}_antipll_#{base_slug}"
    else
      "#{payload_resource}_#{base_slug}"
    end

  category_name = block[/data-category=['"]([^'"]+)['"]/, 1].to_s.strip
  category_name = fallback_category if category_name.empty?

  algorithm_groups = parse_orientation_groups(block, display_name, category_name, algorithm_id_prefix: item_id)
  algorithms =
    if algorithm_groups.empty?
      standard_alg = clean_text(block[/Standard Alg:<\/div>\s*(.*?)\s*<\/div>/m, 1])
      alternatives = block.scan(/<div class="formatted-alg">(.*?)<\/div>/m).flatten.map { |alg| clean_text(alg) }
      d_values = block.scan(/more-algs no-print' data-category='#{Regexp.escape(category_name)}' data-d='(\d+)' data-algname='#{Regexp.escape(display_name)}'/).flatten.uniq
      more_alternatives = fetch_more_algorithms(display_name, category_name, d_values)
      ordered_unique([standard_alg, *alternatives, *more_alternatives])
    else
      ordered_unique(algorithm_groups.flat_map { |group| group['algorithms'].map { |algorithm| algorithm['notation'] } })
    end

  return nil if algorithms.empty?

  item = {
    'id' => item_id,
    'displayName' => display_name,
    'name' => (top_set_name == 'PLL' ? PLL_NAMES.fetch(display_name, "#{display_name} Perm") : display_name),
    'group' => group_name.to_s.strip.empty? ? nil : group_name,
    'subgroup' => subgroup,
    'imageKey' => image_key,
    'recognition' => '',
    'notes' => '',
    'setup' => extract_setup(block),
    'algorithms' => algorithms.each_with_index.map do |notation, index|
      {
        'id' => "#{item_id}-#{index + 1}",
        'notation' => notation,
        'isPrimary' => index.zero?,
        'source' => 'SpeedCubeDB',
        'tags' => []
      }
    end
  }
  item['algorithmGroups'] = algorithm_groups if algorithm_groups.any?

  stickers = parse_stickers(block)
  item['stickers'] = stickers if stickers
  item
end

def collect_cases(url, fallback_category:, payload_resource:, top_set_name:, group_name: nil, visited: Set.new)
  return [] if visited.include?(url)

  visited << url
  html = fetch_url(url)
  blocks = extract_blocks(html)

  if blocks.any?
    return blocks.map do |block|
      parse_block(
        block,
        fallback_category: fallback_category,
        payload_resource: payload_resource,
        top_set_name: top_set_name,
        group_name: group_name
      )
    end.compact
  end

  child_entries = extract_child_entries(html)
  child_paths = child_entries.map(&:first)
  child_entries = child_paths.map { |path| [path, ''] } if child_entries.empty?

  child_entries.flat_map do |path, title|
    next_group_name = group_name || group_title_from_path(top_set_name, path) || normalized_group_title(top_set_name, title)
    collect_cases(
      "https://www.speedcubedb.com/#{path}",
      fallback_category: path.split('/').last,
      payload_resource: payload_resource,
      top_set_name: top_set_name,
      group_name: next_group_name,
      visited: visited
    )
  end
end

def dedup_cases_by_id(cases)
  seen = Set.new
  cases.each_with_object([]) do |item, deduped|
    next unless seen.add?(item['id'])
    deduped << item
  end
end

set_name = ARGV[0] or abort("Usage: #{$PROGRAM_NAME} <set>")
config = SET_CONFIG.fetch(set_name) { abort("Unsupported set: #{set_name}") }
output_path = ARGV[1] || File.expand_path("../CubeFlow/Resources/Algs/#{config[:resource]}.json", __dir__)
page_slug = config[:page] || set_name
page_url = "https://www.speedcubedb.com/a/#{config[:puzzle_path]}/#{page_slug}"
cases = collect_cases(
  page_url,
  fallback_category: page_slug,
  payload_resource: config[:resource],
  top_set_name: set_name
)
cases = dedup_cases_by_id(cases)

payload = {
  'puzzle' => '3x3',
  'set' => set_name,
  'version' => 1,
  'source' => 'SpeedCubeDB',
  'cases' => cases
}

if SETUP_ONLY && File.exist?(output_path)
  existing_payload = JSON.parse(File.read(output_path))
  existing_by_id = existing_payload.fetch('cases', []).each_with_object({}) { |item, map| map[item['id']] = item }
  payload['cases'] = payload['cases'].map do |item|
    existing = existing_by_id[item['id']]
    existing ? merge_setup(existing, item) : item
  end
end

File.write(output_path, JSON.pretty_generate(payload) + "\n")
warn "Generated #{cases.count} #{set_name} cases into #{output_path}"
