require "cryplot"
require "bmp"

def dump(n : Serie)
  x = Cryplot.linspace 0.0, n.period, 100
  Cryplot.plot do
    xlabel "v"
    ylabel "t"
    draw_curve(x, x.map { |t| n[t] }).label "noise"
    legend.at_outside_top
    show
  end
end


def dumpa(l : Lattice)
  w = 50u32
  h = 50u32
  c = ["  ", "..", "°°", "oo", "00", "OO"]
  h_period, v_period = l.period
  (0...h).each do |y|
    (0...w).each do |x|
      r = l[x, y]
      STDOUT << c[(r * c.size).to_i]
    end
    STDOUT << '\n'
  end
end

def dump(l : Lattice)
  w = 400u32
  h = 400u32
  bmp = BMP.new w, h, :depth_24
  (0...h).each do |y|
    (0...w).each do |x|
      r = l[x.to_f64 / 100, y.to_f64 / 100]
      if r < 0
        c = BMP::Color.new red: 255u8 - (-r * 255).to_u8, green: 255u8 - (-r * 255).to_u8, blue: 255
      else
        c = BMP::Color.new red: 255, green: 255u8 - (r * 255).to_u8, blue: 255u8 - (r * 255).to_u8
      end
      bmp.color x, y, c
    end
  end
  File.open "/tmp/truc.bmp", "w" do |io|
    bmp.write io
  end
  `feh /tmp/truc.bmp`
end

abstract class Serie
  abstract def [](t : Float64) : Float64

  class Noise < Serie
    @samples : Array(Float64)
    property period : Float64
    property offset : Float64
    
    def initialize(r = Random::DEFAULT, @period = 1.0, @offset = 0.0, samples = 10)
      @samples = Array(Float64).new(samples) { r.rand }
    end
    
    def [](t : Float64) : Float64
      sample_fit = (@offset + t) % @period / @period * @samples.size
      lo = sample_fit.to_i# % @samples.size
      hi = (lo + 1) % @samples.size
      fit = sample_fit - lo
      smoothed = fit * fit * (3 - 2 * fit)
      @samples[lo] * (1 - smoothed) + @samples[hi] * smoothed
    end
  end
end


abstract class Lattice
  
  abstract def [](x : Float64, y : Float64) : Float64
  
  class Noise < Lattice
    
    def interpolate(a0 : Float64, a1 : Float64, w : Float64)

      #(a1 - a0) * w + a0
      #(a1 - a0) * (3.0 - w * 2.0) + w * w + a0
      i = (a1 - a0) * ((w * (w * 6.0 - 15.0) + 10.0) * w * w * w) + a0
      pp "Interpolate: #{a0} -- #{w} -- #{a1} = #{i}"
      i
    end

    def random(ix : Int32, iy : Int32)
      #r = Random.new(ix*100+iy)
      #a = r.rand - 0.5
      #b = r.rand - 0.5
      #l = Math.sqrt(a ** 2 + b ** 2)
      #{a/l, b/l}

      seeded_random = Random.new ix * 100 + iy
      gradient = (0...2).map { seeded_random.rand - 0.5 }
      length = Math.sqrt gradient.reduce { |a, b| a ** 2 + b ** 2 }
      normal = gradient.map { |corrdinate| corrdinate / length }
      normal
    end

    def dot(ix : Int32, iy : Int32, x : Float64, y : Float64)
      gx, gy = random ix, iy
      dx = x - ix
      dy = y - iy
      #pp "DOT: #{dx} * #{gx} + #{dy} + #{gy} = #{dx * gx + dy * gy}"
      dot = dx * gx + dy * gy
      pp "Gradient: (#{gx} #{gy}) . (#{dx} #{dy}) = #{dot}"
      dot
    end
    
    def [](x : Float64, y : Float64) : Float64
      #pp "----------- X: #{x} Y: #{y}"
      x0 = x.to_i
      x1 = x0 + 1
      y0 = y.to_i
      y1 = y0 + 1

      sx = x - x0
      sy = y - y0

      n0 = dot x0, y0, x, y
      n1 = dot x1, y0, x, y
      #pp "N0: #{n0}"
      #pp "N1: #{n1}"
      
      ix0 = interpolate n0, n1, sx
      #pp "IX0", ix0, n0, n1, sx


      n0 = dot x0, y1, x, y
      n1 = dot x1, y1, x, y

      #pp "N0: #{n0}"
      #pp "N1: #{n1}"

      ix1 = interpolate n0, n1, sx
      #pp "IX1", ix1, n0, n1, sx
      
      r = interpolate ix0, ix1, sy
      #pp "R", r, ix0, ix1, sy
      
      r# * 0.5 + 0.5
    end
  end

end

l = Lattice::Noise.new
l[1.71, 0.0]
#dump l
