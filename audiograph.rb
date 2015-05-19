#
# Demonstration program for recording audio and displaying a moving spectrum (using OpenGL)
#

# For reading the audio:
require 'ffi-portaudio'

# For the FFT:
require 'narray'
require 'fftw3'

# For the OpenGL display:
require 'gl'
require 'glu'
require 'gosu'
require 'glut'

# Audio sample rate and block size:
SAMPLE_RATE = 44100
WINDOW = 4096	    # Updates about 11 times/second
RESOLUTION = (1.0*SAMPLE_RATE/WINDOW)

# Displayed bandwidth:
MIN_FREQ = 150
MIN_BUCKET = (WINDOW*MIN_FREQ/(SAMPLE_RATE)).to_i
MAX_FREQ = 800
MAX_BUCKET = (WINDOW*MAX_FREQ/(SAMPLE_RATE)).to_i

# Displayed lines in terminal mode:
LINES = 30
BUCKETS_PER_LINE = (MAX_BUCKET-MIN_BUCKET)/LINES

class FFTStream < FFI::PortAudio::Stream
  def initialize
    @range = 1000
  end

  def add_sink sink
    @sink = sink
  end

  def process(input, output, frameCount, timeInfo, statusFlags, userData)
    # Read WINDOW*16-bit integer samples and convert to float
    buf = input.read_array_of_int16(frameCount)
    array = NArray.to_na(buf).to_f

    # FFT and take the absolute value (magnitude) of the complex numbers in the array:
    spectrum = FFTW3.fft(array).abs

    if @sink
      @sink.set_data spectrum.to_a[MIN_BUCKET, MAX_BUCKET]
    else
      terminal_show(spectrum)
     end

    :paContinue
  end

  # If no data sink is set, display using text
  def terminal_show spectrum
    print "\e[2J\e[H"
    puts "Spectrum"
    bucket = MIN_BUCKET
    max = 0
    spectrum.to_a[MIN_BUCKET, LINES*BUCKETS_PER_LINE].each_slice(BUCKETS_PER_LINE) do |a|
      sum = a.inject(0, :+)
      max = sum if max < sum
      @range = sum if @range < sum    # Range down immediately or it's ugly
      freq = (bucket+BUCKETS_PER_LINE/0.5) * RESOLUTION
      bucket += BUCKETS_PER_LINE
      puts "#{freq.to_i}\t" + ("*" * (sum * 50 / @range).to_i)
    end
    @range = max if max < @range/5 or max > @range    # Auto-range up or down
  end

end

def MonoAudioInput
  input = FFI::PortAudio::API::PaStreamParameters.new
  input[:device] = FFI::PortAudio::API.Pa_GetDefaultInputDevice
  input[:channelCount] = 1
  input[:sampleFormat] = FFI::PortAudio::API::Int16
  input[:suggestedLatency] = 0
  input[:hostApiSpecificStreamInfo] = nil
  input
end

class SpectrumDisplay < Gosu::Window
  include Gl
  include Glu

  def initialize
    super(1000, 600, false)
    self.caption = "Audio Spectrum"
    @data = []
    @range = 0.01
  end

  def set_data data
    @data = data
  end

  def generate_noise
    origin = 0.5	# Centre the display vertically
    h = origin		# Start at the origin
    noise = 0.1		# Inject this ratio of max amplitude each
    density = 1		# Likelihood of any vertex having new noise
    decay = 0.95	# Ratio of previous signal that remains
    @data = (0..width).map do |i|
      pulse = (rand < density) ? (rand-0.5)*noise : 0
      h = (h-origin+pulse)*decay + origin
      @data[i] = h
    end
  end

  def update
  end

  def draw
    gl do
      window_ratio = (0.0+width)/height
      glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
      glMatrixMode(GL_PROJECTION) # see lesson01
      glLoadIdentity  # see lesson01
      gluPerspective(
	90.0,			# field of view angle in y direction
	window_ratio,		# aspect ratio to determine x field of view
	0.1,			# Distance to near clipping plane
	100.0			# distance to far clipping plane
      )
      glMatrixMode(GL_MODELVIEW)
      glLoadIdentity

      # Put 0,0 at the bottom left
      # The top will be y=1, the right x=window_ratio
      glTranslatef(-window_ratio/2, -0.5, -0.5)	# x, y, z

      # Display the line graph from "data"
      max = 0
      glBegin(GL_LINE_STRIP)
	# generate_noise
	@data.each_with_index do |h, i|
	  max = h if max < h  # Max this pass
	  x = window_ratio*i/@data.size
	  glVertex3f(x, h/@range, 0)
	end
      glEnd
      @range = max if max < @range/5 or max > @range    # Auto-range down or up
    end
  end

  def button_down(id)
    case id
    when Gosu::KbEscape
      close
    #when Gosu::KbUp
    #when Gosu::KbDown
    #when Gosu::KbLeft
    #when Gosu::KbRight
    else
      puts "Key id=#{id}"
    end
  end
end

FFI::PortAudio::API.Pa_Initialize

input = MonoAudioInput()

window = SpectrumDisplay.new
stream = nil
Thread.new do
  stream = FFTStream.new
  stream.open(input, nil, SAMPLE_RATE, WINDOW)
  stream.add_sink window
  stream.start
end

at_exit {
  stream.close
  FFI::PortAudio::API.Pa_Terminate
}
Signal.trap("INT") { exit }

#loop { sleep 1 }
window.show
