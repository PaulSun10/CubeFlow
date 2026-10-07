require 'json'
keys=%w[algs.direction settings.font_downloading algs.probability algs.orientation.normal algs.orientation.inverted algs.execution_alignment data.move.confirm event.fto algs.item.sq1pbl.title algs.item.sq1pbl.description algs.item.ftoedges.title algs.item.ftoedges.description algs.item.sq1obl.title algs.item.sq1obl.description algs.item.sq1csp.title algs.item.sq1csp.description algs.subset.odd algs.subset.even algs.subset.non_parity algs.subset.parity algs.sort algs.sort_default algs.sort_likely algs.sort_unlikely algs.sort_slices algs.probability_basis settings.diagram_stroke settings.diagram_stroke_thin settings.diagram_stroke_medium settings.diagram_stroke_thick]
files=Dir['CubeFlow/*.lproj/Localizable.strings']; files.each do |p|
 s=File.read(p);pairs=s.scan(/^"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)";/);dict=pairs.to_h
 duplicates=pairs.group_by(&:first).select{|k,v|v.length>1};raise "duplicates #{p}: #{duplicates.keys}" unless duplicates.empty?
 keys.each{|key|raise "missing #{p} #{key}" unless dict[key]&& !dict[key].empty?}
 raise "bad placeholder #{p}" unless dict['data.move.confirm'].scan(/%@/).length==1
 raise "plutil failed #{p}" unless system('plutil','-lint',p,out:File::NULL)
end
puts "#{files.length} catalogs: syntax, duplicate keys, depth correction keys and confirmation placeholders passed"
