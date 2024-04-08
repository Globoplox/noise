require "option_parser"
require "bmp"
require "./noise"
require "./lang"

output = STDOUT
colors = BMP::GRAYSCALE_8BPP
width = 400u32
height = 400u32
noise = Noise.new
expression = nil
resolution = 100u32
  
OptionParser.parse do |parser|
  parser.banner = "usage: <name> [options] [expression]"

  parser.on "-o path", "--output path", "Output file path" do |path|
    output = path
  end

  parser.on "-w width", "--width width", "Set output picture width" do |w|
    width = w.to_u32
  end

  parser.on "-r resolution", "--resolution resolution", "Set amount of pixel per 1.0 distance in noise" do |r|
    resolution = r.to_u32
  end

  parser.on "-h height", "--height height", "Set output picture height" do |h|
    height = h.to_u32
  end

  parser.on "-H", "--help", "Show help" do
    puts parser
    exit
  end

  parser.on "-c color", "--colors color", "Set the color to use as rgb range: '0,0,0-255,255,0'" do |color_spec|
    ranges = color_spec.split('-', remove_empty: true).map do |range|
      r,g,b = range.split(',', remove_empty: true).map &.to_i
      {r, g ,b}
    end
    
    raise "Color ranges must specify at least to colors" unless ranges.size >= 2
    
    colors = (0u8...256).map do |i|
      step = 256 / (ranges.size - 1)
      lo = i // step
      hi = i // step + 1
      lo_r, lo_g, lo_b  = ranges[lo]
      hi_r, hi_g, hi_b = ranges[hi]
      w = (i % step.to_i) / 256 * (ranges.size - 1)
      r = lo_r + (hi_r - lo_r) * w
      g = lo_g + (hi_g - lo_g) * w
      b = lo_b + (hi_b - lo_b) * w
      BMP::Color.new r.to_u8, g.to_u8, b.to_u8
    end
  end 

  parser.unknown_args do |before, after|
    args = before + after
    raise "Only a sinle expression is allowed" if args.size > 1
    expression = args.first?
  end
end

noise = expression.try do |expression|
  Noise::Lang::Parser.new(IO::Memory.new expression).expression.build
end || Noise.new

case noise
in Float64 
  bmp = BMP.fill8bpp(width, height) do |x, y|
    (noise * 128 + 128).clamp(0u8, 255u8).to_u8
  end
in Noise
  bmp = BMP.fill8bpp(width, height) do |x, y|
    (noise[x / resolution, y / resolution] * 128 + 128).clamp(0u8, 255u8).to_u8
  end
end

bmp.color_table = colors

begin 
  o = output
  case o
  when IO then bmp.write o
  when String, Path then File.open o, "w" { |io| bmp.write io }
  end
end
