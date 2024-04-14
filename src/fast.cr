# Noise generator faster than `Noise` but specialized into
# filling 2D UInt8 bitmaps.
module Noise::Fast2D
  extend self

  def interpolate(a0 : Float64, a1 : Float64, w : Float64)
    (a1 - a0) * ((w * (w * 6.0 - 15.0) + 10.0) * w * w * w) + a0
  end
  
  def gradients(x : Int32, y : Int32) : Indexable(Float64)
    seed = x &* 100 &+ y
    seeded_random = Random.new seed
    gradient = { (seeded_random.rand - 0.5) * 2, (seeded_random.rand - 0.5) * 2 }
    length = Math.sqrt gradient.reduce { |a, b| a ** 2 + b ** 2 }
    normal = gradient.map { |corrdinate| corrdinate / length }
    normal
  end

  def noise(width : UInt32, height : UInt32, resolution : UInt32, data : Bytes, x_offset : Int32 = 0, y_offset : Int32 = 0)
    upper_gradient_cache = Slice({Float64, Float64}).new(width.to_i + 1) { |i| self.gradients x_offset + i, y_offset }
    lower_gradient_cache = Slice({Float64, Float64}).new width.to_i + 1, {0.0, 0.0}
    gradient_y = 0
    step = 1/ resolution
    
    while gradient_y < height
      lower_gradient_cache.fill { |i| self.gradients x_offset + i, y_offset + gradient_y + 1}
      gradient_x = 0
      while gradient_x < width        
        ga = upper_gradient_cache[gradient_x]
        gb = upper_gradient_cache[gradient_x + 1]
        gc = lower_gradient_cache[gradient_x]
        gd = lower_gradient_cache[gradient_x + 1]

        y = 0.0
        py = 0
        while py < resolution
          x = 0.0
          px = 0
          while px < resolution
            da = {x - (x.to_i + 0), y - (y.to_i + 0)}
            db = {x - (x.to_i + 1), y - (y.to_i + 0)}
            dc = {x - (x.to_i + 0), y - (y.to_i + 1)}
            dd = {x - (x.to_i + 1), y - (y.to_i + 1)}
            a = ga[0] * da[0] + ga[1] * da[1]
            b = gb[0] * db[0] + gb[1] * db[1]
            c = gc[0] * dc[0] + gc[1] * dc[1]
            d = gd[0] * dd[0] + gd[1] * dd[1]
            sx = x - x.to_i
            sy = y - y.to_i
            i1 = interpolate a, b, sx
            i2 = interpolate c, d, sx
            i3 = interpolate i1, i2, sy
            data[(gradient_y * resolution + py) * (width * resolution) + (gradient_x * resolution) + px] =
              (i3 * 128 + 128).clamp(0u8, 255u8).to_u8
            px += 1
            x += step
          end
          py += 1
          y += step
        end
        gradient_x += 1
      end
      upper_gradient_cache, lower_gradient_cache = {lower_gradient_cache, upper_gradient_cache,}
      gradient_y += 1
    end
  end

  def concurrent(
       width : UInt32, height : UInt32,
       resolution : UInt32,
       data : Bytes,
       x_offset : Int32 = 0, y_offset : Int32 = 0,
       workers : UInt8 = 0
  )
    workers = height if workers > height
    channels = Array(Channel(Nil)).new(workers) do |worker_index|
      local_height_offset = worker_index * (height // workers)
      local_height = (height // workers).clamp nil, height - worker_index * (height // workers)
      local_data = data + local_height_offset * width * resolution * resolution
      local_y_offset = local_height_offset + y_offset
      channel = Channel(Nil).new
      spawn do
        noise width, local_height, resolution, local_data, x_offset, local_y_offset
        channel.send nil
      end
      channel
    end
    channels.each &.receive
  end
end
