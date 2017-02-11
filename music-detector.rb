require 'ruby-audio'
require 'numru/fftw3'

include NumRu

INPUT_BUFFER_SIZE = 1024

TEMPERAMENT_RANGE = -12..24
TEMPERAMENT_SEPARATOR_RANGE = (-12..25).to_a.map { |i| i - 0.5 }.freeze
A = 440

# @param [String] file     path of the input audio file
# @param [Float]  seektime seek time in the audio file (in seconds)
# @param [Float]  duration duration in the audio file (in seconds)
# @return [Array<Float>, Float] monoauralized wave and samplerate
def read_audio_file(file:, seektime:, duration:)
  RubyAudio::Sound.open(file) do |sound|
    samplerate = sound.info.samplerate
    channels = sound.info.channels

    sound.seek((seektime * samplerate).round)

    buffer = RubyAudio::Buffer.new(:short, INPUT_BUFFER_SIZE, channels)

    sample_count = (duration * samplerate).round
    mono_wave = Array.new(sample_count)

    count = 0
    while count < sample_count
      read_count = sound.read(buffer, [INPUT_BUFFER_SIZE, sample_count - count].min)
      read_count.times do |i|
        mono_wave[count + i] = buffer[i].inject(&:+) / channels # monoauralize
      end

      count += read_count
      break if read_count < INPUT_BUFFER_SIZE
    end

    [mono_wave, samplerate]
  end
end

def equal_temperament(range:, a:)
  range.map { |i| a * 2 ** (i / 12.0) }
end


# read audio file
wave, samplerate = read_audio_file(file: 'music.wav', seektime: 1.0, duration: 1.2)

# do fft and make frequency spectrum
length = wave.length / 2
spectrum = FFTW3.fft(wave, FFTW3::FORWARD).abs[0...length]
frequencies = (0...length).map { |i| i.to_f / length * samplerate / 2 } # frequencies of each element in spectrum

# prepare equal temperament
temperament = equal_temperament(range: TEMPERAMENT_RANGE, a: A)
temperament_separator = equal_temperament(range: TEMPERAMENT_SEPARATOR_RANGE, a: A)



# File.open('test.csv', 'w') do |file|
#   spectrum.each do |s|
#     file.write(s.to_s + "\n")
#   end
# end
