require 'wavefile'
require 'numru/fftw3'
require 'linear-regression'

module MusicDetector
  class FeatureVector
    include NumRu

    TEMPERAMENT_RANGE = -12..24
    A = 440

    HPF_FREQ = 100
    LPF_FREQ = 2000

    IN_TUNE_RATIO = 0.1
    OUT_OF_TUNE_RATIO = 3

    attr_reader(:vector)

    def initialize(file:, seektime:, duration:, debug: false)
      # read audio file
      wave, samplerate = read_audio_file(file: file, seektime: seektime, duration: duration)

      # do fft and make frequency spectrum
      length      = wave.length / 2
      spectrum    = FFTW3.fft(wave, FFTW3::FORWARD).abs[0...length]
      frequencies = NArray.to_na((0...length).map { |i| i.to_f / length * samplerate / 2 }) # frequencies of each element in spectrum

      puts("input file: #{file} (samplerate: #{samplerate}Hz)") if debug

      # bandpath filter (to faster computation)
      spectrum, frequencies = band_path_filter(spectrum: spectrum, frequencies: frequencies, hpf_freq: HPF_FREQ, lpf_freq: LPF_FREQ)

      # prepare for analysis
      log_frequencies = NMath::log(frequencies)
      log_temperament = NMath::log(equal_temperament(range: TEMPERAMENT_RANGE, a: A))

      log_bin_freq_half_bandwidth     = (log_temperament[1] - log_temperament[0]) / 2.0
      log_in_tune_freq_half_bandwidth = log_bin_freq_half_bandwidth * IN_TUNE_RATIO

      puts("log(bin_half_bandwidth)=#{log_bin_freq_half_bandwidth}\n") if debug
      power_tune_ratio = log_temperament.map do |log_bin_center_freq|
        puts(sprintf("f = %4.3f, log(f) = %.3f", Math::exp(log_bin_center_freq), log_bin_center_freq)) if debug

        # indices of the target bin (for spectrum)
        log_bin_indices = (log_frequencies - log_bin_center_freq).abs < log_bin_freq_half_bandwidth

        # extract the target bin
        target_log_frequencies = log_frequencies[log_bin_indices]
        target_spectrum        = spectrum[log_bin_indices]

        # calc ratio between in-tune and out-of-tune powers
        target_in_tune_indices     = (target_log_frequencies - log_bin_center_freq).abs <= log_in_tune_freq_half_bandwidth
        target_out_of_tune_indices = (target_log_frequencies - log_bin_center_freq).abs >  log_in_tune_freq_half_bandwidth * OUT_OF_TUNE_RATIO

        in_tune_power     = target_spectrum[target_in_tune_indices].mean
        out_of_tune_power = target_spectrum[target_out_of_tune_indices].mean

        in_tune_power / out_of_tune_power
      end

      @vector = power_tune_ratio.sort.reverse
    end

    private

    # @param [String] file     path of the input audio file
    # @param [Float]  seektime seek time in the audio file (in seconds)
    # @param [Float]  duration duration in the audio file (in seconds)
    # @return [Array<Float>, Float] monoauralized wave and samplerate
    def read_audio_file(file:, seektime:, duration:)
      mono_wave = nil
      samplerate = nil

      WaveFile::Reader.new(file) do |sound|
        samplerate = sound.format.sample_rate
        channels = sound.format.channels

        # seek
        sound.read((seektime * samplerate).round)

        # read
        sample_count = (duration * samplerate).round
        mono_wave = NArray.sint(sample_count)

        sound.read(sample_count).samples.each.with_index do |sample, i|
          case sample
          when Array
            mono_wave[i] = sample.inject(&:+) / channels # normalize to monoral
            mono_wave[i] *= (2 ** (bits_per_sample - 1)) if Float === sample.first
          when Fixnum
            mono_wave[i] = sample
          when Float
            mono_wave[i] = sample * (2 ** (bits_per_sample - 1))
          else
            raise StandardError("unsupported file: #{file}")
          end
        end
      end

      [mono_wave, samplerate]
    end

    def band_path_filter(spectrum:, frequencies:, hpf_freq:, lpf_freq:)
      bpf_indices = (HPF_FREQ < frequencies) * (frequencies < LPF_FREQ)
      spectrum    = spectrum[bpf_indices]
      frequencies = frequencies[bpf_indices]
      [spectrum, frequencies]
    end

    def equal_temperament(range:, a:)
      NArray.to_na(range.map { |i| a * 2 ** (i / 12.0) })
    end

  end
end

negative_example_dir = ARGV[0]
positive_example_dir = ARGV[1]
negative_example_dir = negative_example_dir + '/' unless negative_example_dir.end_with?('/')
positive_example_dir = positive_example_dir + '/' unless positive_example_dir.end_with?('/')

negative_fvs = Dir.entries(negative_example_dir)
                 .map { |f| "#{negative_example_dir}#{f}" }
                 .select { |f| f.end_with?('.wav') }
                 .map { |f| p f; MusicDetector::FeatureVector.new(file: f, seektime: 0, duration: 3.2).vector }
positive_fvs = Dir.entries(positive_example_dir)
                 .map { |f| "#{positive_example_dir}#{f}" }
                 .select { |f| f.end_with?('.wav') }
                 .map { |f| p f; MusicDetector::FeatureVector.new(file: f, seektime: 0, duration: 3.2).vector }

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

tp = 0
fp = 0
tn = 0
fn = 0
p calculated_y
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
