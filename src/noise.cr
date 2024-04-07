# Module for generating n dimensions perlin like noise
class Noise
  @frequencies : Indexable(Float64?)
  @offsets : Indexable(Float64?)
  @periods : Indexable(UInt32?)
  @intensity_multiplier : Float64
  @intensity_gain : Float64
  @child : Noise?

  def periods=(periods = Slice(Float64?))
    raise "Cannot set periods on non root noise" if @child
    @periods = periods.map &.as UInt32?
  end

  # Initialize a periodic noise. It must be the root noise to be periodic.
  def initialize(
    periods : Indexable(UInt32?), 
    frequencies = Slice(Float64?).empty, 
    offsets = Slice(Float64?).empty, 
    @intensity_multiplier = 1.0, 
    @intensity_gain = 0.0, 
  )
    @frequencies = frequencies.map &.as Float64?
    @offsets = offsets.map &.as Float64?
    @periods = periods.map &.as UInt32?
  end

  # Initialize a non-periodic noise. It can be a root noise ot just parameters added
  # on top of another noise.
  def initialize(
    frequencies = Slice(Float64?).empty, 
    offsets = Slice(Float64?).empty, 
    @intensity_multiplier = 1.0, 
    @intensity_gain = 0.0, 
    @child = nil
  )
    @frequencies = frequencies.map &.as Float64?
    @offsets = offsets.map &.as Float64?
    @periods = Slice(UInt32?).empty
  end
  
  # Simple smootherstep interpolation function
  def interpolate(a0 : Float64, a1 : Float64, w : Float64)
    (a1 - a0) * ((w * (w * 6.0 - 15.0) + 10.0) * w * w * w) + a0
  end

  def [](*coordinates : Float64) : Float64
    (@child || self).raw(
      *coordinates.map_with_index { |c, i| 
        c = c * (@frequencies[i]? || 1.0) + (@offsets[i]? || 1.0) 
      }
     ) * @intensity_multiplier + @intensity_gain
  end

  # Generate noise value for the given coordinates and gradients
  def raw(*coordinates : Float64)
    products = Indexable
    .cartesian_product((0...(coordinates.size)).map { {0, 1} })
    .map(&.reverse)
    .map { |modifiers| 
      g = gradients((0...(coordinates.size)).map { |dimension| 
        coordinates[dimension].to_i + modifiers[dimension]
      })

      distance = (0...(coordinates.size)).map { |dimension| 
        coordinates[dimension] - (coordinates[dimension].to_i + modifiers[dimension]) 
      }

      (0...(coordinates.size)).sum { |dimension|
        g[dimension] * distance[dimension]
      }
    }

    (0...(coordinates.size)).map { |dimension| 
      s = coordinates[dimension] - coordinates[dimension].to_i
      products = (0...(2 ** ((coordinates.size) - dimension - 1))).map { |n|
        interpolate products[n * 2], products[n * 2 + 1], s
      }
    }

    products.first
  end

  def gradients(coordinates : Indexable(Int32)) : Indexable(Float64)
    coordinates = coordinates.map_with_index { |c, i| 
      @periods[i]?.try { |period| c - c % period } || c
    }
    seed = coordinates[0] * 100 + coordinates[1]
    seeded_random = Random.new seed
    gradient = (0...(coordinates.size)).map { seeded_random.rand - 0.5 }
    length = Math.sqrt gradient.reduce { |a, b| a ** 2 + b ** 2 }
    gradient.map { |corrdinate| corrdinate / length }
  end

  class Sum < Noise
    @noises : Indexable(Noise)
    
    def initialize(noises)
      super()
      @noises = noises.map &.as Noise
    end

    def [](*coordinates : Float64) : Float64
      transformed = coordinates.map_with_index { |c, i| 
        c = c * (@frequencies[i]? || 1.0) + (@offsets[i]? || 1.0) 
      }
      @noises.sum { |noise| noise[*transformed] } * @intensity_multiplier + @intensity_gain
    end

    def +(other : Noise)
      Sum.new(@noises.to_a + [other])
    end

    def periods=(periods : Slice(Float64?))
      raise "Cannot set periods on non root noise"
    end
  
  end

  def *(other : Float64) : Noise
    Noise.new intensity_multiplier: other, child: self
  end

  def /(other : Float64) : Noise
    self * (1 / other)
  end

  def +(other : Float64) : Noise
    Noise.new intensity_gain: other, child: self
  end

  def -(other : Float64) : Noise
    self + -other
  end

  def + : Noise
    self
  end

  def - : Noise
    self * -1
  end

  def +(other : Noise) : Noise
    Sum.new(Slice[self, other])
  end

  def -(other : Noise) : Noise
    self + -other
  end

  def *(other : Noise) : Noise
    raise "Nosie multiplication is not supported yet"
  end

  def /(other : Noise) : Noise
    raise "Noise division is not supported yet"
  end
end

struct Float64
  def +(other : Noise) : Noise
    other + self
  end

  def -(other : Noise) : Noise
    other - self
  end

  def *(other : Noise) : Noise
    other * self
  end

  def /(other : Noise) : Noise
    other / self
  end
end