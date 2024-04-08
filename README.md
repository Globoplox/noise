# Noise
65;7402;1c
Generate perlin noise.
For fun pet-project.

## Installation

Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     noise:
       github: globoplox/noise
   ```

## Usage

## Programmatic

A simple plot of a 1d noise:
```cr
require "noise"

noise = Noise.new

heights = (0...100).map do |t|
  (noise[t / 20] + 1) * 10
end

(0...20).each do |l|
  heights.each do |v|
    if v >= (20 - l)
      STDOUT << '#'
    else
      STDOUT << ' '
    end
  end
  STDOUT << '\n'
end
```

Basic noise function output a value between `-1.0` and `1.0`.

The noise function work at any order, based on the number of coordinates given:

```cr
require "noise"

chars_2d = [' ', '.', '°', 'o', '0', 'O']

noise = Noise.new

(0...50).each do |y|
  (0...50).each do |x|
    v = noise[x / 10, y / 10]
    c = chars_2d[((v + 1) / 2 * chars_2d.size).to_i]
    STDOUT << c
    STDOUT << c
  end
  STDOUT << '\n'
end
```

Noise can be periodic and can be warpped into transformations, including:
- Offsets
- Frequencies
- Gain (by multiplication and addition)
- Sum of noise function

```cr
noise = Noise.new(
  offsets: {1.0, 0.0},
  child: (
    Noise.new(periods: {5u32, 5u32}) +
    Noise.new(frequencies: {4.0, 4.0}) / 4) -
  0.25
)
```

## Standalone

Come with a standalone CLI tool for generating 2D perlin noise pictures:

Exemples:

Build a 400x400 pixel grayscale bitmap with 100x100 pixels within each gradient cell. 
`./bin/cli > noise.bmp`

Build a 100x100 pixel bitmap with 10x10 pixels within each gradient cell. 
`./bin/cli --width 100 -height 100 --resolution 10 > noise.bmp`

Colors output can be customized:
`./bin/cli --colors '255,0,0 - 255,255,255 - 0,0,255' > noise.bmp`
In this example, the color space is divided in two continuous range: 
- from pure red (rgb 255, 0, 0) to pure white (rgb 255, 255, 255)
- from pure white (rgb 255, 255, 255) to pure blue (rgb 0, 0, 255)

Each color is specified in rgb format `<red: 0-255>,<green: 0-255>,<blue: 0-255>`
There can be from 2 to any number of color, the color space will span evenly on each ranges.

The noise function that is drawn can be customized:
`./bin/cli --colors '255,0,0 - 255,255,255 - 0,0,255' 'n + n[freq 2] / 2 + n[freq 4] / 4'  > noise.bmp`

The noise function is specified as an expression:
- `n` is a simple noise function
- `n + 1.0` for controlling gain: `n + 1`, `n + -2.76`, `n - 0.05`
- `n * 0.5` for controlling intensity: `n * 2`, `n / 2`, `n * 0.5`, `n * 1 / 2`
- `n + n` for adding noise function together
- `n + n * 2` expected operation order and associativity applies
- `(n + n) * 2` parenthesis can be used
- `n + n[offset 0.5]` noise function can be transformed by offseting it
- `n + n[freq 10.0]` noise fucntion can be transformed by increasing the frequency
- `n + n[freq 10.0 offset 0.5]` parameters can be grouped
- `n + n[freq 2][freq 2]` transformations can be chained
- `n[period 5 freq 3]` a root noise function (not transformed or composed of computation of other noise) can be made periodic
- `n[period x:5 freq 3]` period, frequency and offset parameters can be set for a specific dimension

Example: `n + n[freq 2] / 2 + n[freq 4] / 4 + n[freq 8] / 8`

## Performance

There were no significant effort for high performance invloved in this project.  
It focus toyability by provding customizable generics.
