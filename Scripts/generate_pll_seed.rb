#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "json"
require "open3"
require "shellwords"
require "tempfile"

PLL_NAMES = {
  "Aa" => "Aa Perm",
  "Ab" => "Ab Perm",
  "E" => "E Perm",
  "F" => "F Perm",
  "Ga" => "Ga Perm",
  "Gb" => "Gb Perm",
  "Gc" => "Gc Perm",
  "Gd" => "Gd Perm",
  "H" => "H Perm",
  "Ja" => "Ja Perm",
  "Jb" => "Jb Perm",
  "Na" => "Na Perm",
  "Nb" => "Nb Perm",
  "Ra" => "Ra Perm",
  "Rb" => "Rb Perm",
  "T" => "T Perm",
  "Ua" => "Ua Perm",
  "Ub" => "Ub Perm",
  "V" => "V Perm",
  "Y" => "Y Perm",
  "Z" => "Z Perm"
}.freeze

def clean_text(value)
  CGI.unescape_html(value.to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip)
end

def ordered_unique(values)
  seen = {}
  values.each_with_object([]) do |value, result|
    next if value.nil? || value.empty? || seen[value]

    seen[value] = true
    result << value
  end
end

def fetch_more_algorithms(display_name)
  cookie_file = Tempfile.new(["speedcubedb", ".cookies"])
  cookie_path = cookie_file.path
  cookie_file.close

  case_url = "https://www.speedcubedb.com/a/3x3/PLL/#{display_name}"
  more_url = "https://www.speedcubedb.com/category.algs.php?algname=#{display_name}&d=0&cat=PLL"
  user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
  referer = "https://www.speedcubedb.com/a/3x3/PLL/#{display_name}"

  begin
    Open3.capture3("curl", "-sS", "-L", "-c", cookie_path, case_url)
    stdout, stderr, status = Open3.capture3(
      "curl",
      "-sS",
      "-L",
      "-b", cookie_path,
      "-c", cookie_path,
      "-A", user_agent,
      "-H", "Accept: */*",
      "-H", "Accept-Language: en-US,en;q=0.9",
      "-H", "Referer: #{referer}",
      "-H", "Sec-Fetch-Dest: empty",
      "-H", "Sec-Fetch-Mode: cors",
      "-H", "Sec-Fetch-Site: same-origin",
      "-H", "X-Requested-With: XMLHttpRequest",
      more_url
    )
    warn stderr unless status.success? || stderr.to_s.strip.empty?
    return [] unless status.success?

    stdout.scan(/<div class="formatted-alg">(.*?)<\/div>/m).flatten.map { |alg| clean_text(alg) }
  ensure
    cookie_file.unlink
  end
end

input_path = ARGV[0] || "/tmp/speedcubedb_pll.html"
output_path = ARGV[1] || File.expand_path("../CubeFlow/Resources/Algs/pll.json", __dir__)

html = File.read(input_path)

blocks = html.scan(/(<div class="row singlealgorithm g-0".*?)(?=<div class="row singlealgorithm g-0"|\z)/m).flatten

cases = blocks.map do |block|
  display_name = block[/data-alg="([^"]+)"/, 1]
  subgroup = block[/data-subgroup="([^"]+)"/, 1]
  next if display_name.nil? || display_name.empty?

  standard_alg = clean_text(block[/Standard Alg:<\/div>\s*(.*?)\s*<\/div>/m, 1])
  alternatives = block.scan(/<div class="formatted-alg">(.*?)<\/div>/m).flatten.map { |alg| clean_text(alg) }
  more_alternatives = fetch_more_algorithms(display_name)
  algorithms = ordered_unique([standard_alg, *alternatives, *more_alternatives])
  sticker_data = {
    "us" => block[/data-us="([^"]+)"/, 1].to_s,
    "ub" => block[/data-ub="([^"]+)"/, 1].to_s,
    "uf" => block[/data-uf="([^"]+)"/, 1].to_s,
    "ul" => block[/data-ul="([^"]+)"/, 1].to_s,
    "ur" => block[/data-ur="([^"]+)"/, 1].to_s
  }

  next({
    "id" => display_name.downcase,
    "displayName" => display_name,
    "name" => PLL_NAMES.fetch(display_name, "#{display_name} Perm"),
    "subgroup" => subgroup.to_s,
    "imageKey" => "pll_#{display_name.downcase}",
    "stickers" => sticker_data,
    "recognition" => "",
    "notes" => "",
    "algorithms" => algorithms.each_with_index.map do |notation, index|
      {
        "id" => "#{display_name.downcase}-#{index + 1}",
        "notation" => notation,
        "isPrimary" => index.zero?,
        "source" => "SpeedCubeDB",
        "tags" => []
      }
    end
  })
end.compact

payload = {
  "puzzle" => "3x3",
  "set" => "PLL",
  "version" => 1,
  "source" => "SpeedCubeDB",
  "cases" => cases.sort_by { |item| item["displayName"] }
}

File.write(output_path, JSON.pretty_generate(payload) + "\n")

warn "Generated #{cases.count} PLL cases into #{output_path}"
