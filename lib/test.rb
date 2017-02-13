require './music_detector/feature_vector_extractor'

negative_example_dir = ARGV[0]
positive_example_dir = ARGV[1]
negative_example_dir = negative_example_dir + '/' unless negative_example_dir.end_with?('/')
positive_example_dir = positive_example_dir + '/' unless positive_example_dir.end_with?('/')

fv_extractor = MusicDetector::FeatureVectorExtractor.new()
negative_fvs = Dir.entries(negative_example_dir)
                 .map { |f| "#{negative_example_dir}#{f}" }
                 .select { |f| f.end_with?('.wav') }
                 .map { |f| p f; fv_extractor.extract_from(file: f, seektime: 0, duration: 3.2) }
positive_fvs = Dir.entries(positive_example_dir)
                 .map { |f| "#{positive_example_dir}#{f}" }
                 .select { |f| f.end_with?('.wav') }
                 .map { |f| p f; fv_extractor.extract_from(file: f, seektime: 0, duration: 3.2) }

NEGATIVE = -1
POSITIVE = 1

negative_count = negative_fvs.count
positive_count = positive_fvs.count
fv_length = negative_fvs.first.total

x = NMatrix.float(fv_length + 1, negative_count + positive_count)
y = NVector.float(negative_count + positive_count)

x[0, true] = NVector.int(negative_count + positive_count).fill(1)
negative_fvs.each.with_index do |fv, i|
  x[1..fv_length, i] = fv
  y[i] = NEGATIVE
end
positive_fvs.each.with_index do |fv, i|
  x[1..fv_length, negative_count + i] = fv
  y[negative_count + i] = POSITIVE
end

puts "x:"
p x

b = (x.transpose * x).inverse * x.transpose * y
puts "b:"
p b

calculated_y = x * b
puts "calculated y:"
p calculated_y

tp = 0
fp = 0
tn = 0
fn = 0
calculated_y.each.with_index do |r, i|
  tp += 1 if 0 <= r && y[i] == POSITIVE
  fp += 1 if 0 <= r && y[i] == NEGATIVE
  fn += 1 if r < 0 && y[i] == POSITIVE
  tn += 1 if r < 0 && y[i] == NEGATIVE
end
puts("tp=#{tp}, fp=#{fp}, fn=#{fn}, tn=#{tn}")
puts("accuracy=#{(tp + tn).to_f / (tp + fp + fn + tn)}, precision=#{tp.to_f / (tp + fp)}, recall=#{tp.to_f / (tp + fn)}")

# File.open('test.csv', 'w') do |file|
#   frequencies.each do |i|
#     file.write(i.to_s + "\n")
#   end
# end


# without constant term
#tp=16, fp=2, fn=11, tn=102
#accuracy=0.9007633587786259, precision=0.8888888888888888, recall=0.5925925925925926

# with constant term
#tp=21, fp=1, fn=6, tn=103
#accuracy=0.9465648854961832, precision=0.9545454545454546, recall=0.7777777777777778
