require "../noise"

module Noise::Lang

  class AST

    # Root AST node for all expressions.
    abstract class Expression < AST
      # Naively produce the value reprensented by the AST
      # since the expression are simples, there is no need for any external visitor.
      abstract def build : Float64 | ::Noise
    end

    class Unary < Expression
      def initialize(@operator : String, @right : Expression)
      end

      def build : Float64 | ::Noise
        got = @right.build
        case @operator
        when "+" then got
        when "-" then -got
        else raise "Unexpected operator '#{@operator}"
        end
      end
    end

    class Binary < Expression
      def initialize(@left : Expression, @operator : String, @right : Expression)
      end

      def build : Float64 | ::Noise
        left = @left.build
        right = @right.build
        case @operator
        when "+" then left + right
        when "-" then left - right
        when "*" then left * right
        when "/" then left / right
        else raise "Unexpected operator '#{@operator}"
        end
      end
    end

    abstract class Literal < Expression
    end
    
    class Number < Literal
      def initialize(@value : Float64) 
      end

      def build : Float64 | ::Noise
        @value
      end
    end

    class Noise < Literal
      def initialize(@name : String)
      end
      
      def build : Float64 | ::Noise
        ::Noise.new
      end
    end

    class Parameter < AST
      getter name, dimension, value
      def initialize(@name : String, @dimension : UInt32?, @value : Float64)
      end
    end
    
    class Parameters < Expression
      def initialize(@target : Expression, @parameters : Array(Parameter))
      end

      # Fallback to 4D for now, TODO: supports dimension wildcards parameters
      # This is not very well thought.
      # TODO: fix it
      def dimension_parameters_to_indexable(parameters : Array(Parameter))
        default = parameters.find &.dimension.nil?
        r = Array(Float64?).new(4, default.try &.value)
        parameters.each do |parameter|
          dim = parameter.dimension
          r[dim] = parameter.value if dim
        end
        r
      end

      def build : Float64 | ::Noise
        sub = @target.build
        case sub
        in Float64 then raise "Cannot apply noise parameters to a scalar value"
        in ::Noise
          frequencies = dimension_parameters_to_indexable @parameters.select(&.name.== "frequency")
          offsets = dimension_parameters_to_indexable @parameters.select(&.name.== "offset")
          if @parameters.any? &.name.== "period"
            if @target.class == AST::Noise
              periods = dimension_parameters_to_indexable(@parameters.select(&.name.== "period")).map &.try &.to_u32
              ::Noise.new periods: periods, frequencies: frequencies, offsets: offsets
            else
              raise "Periods parameters can be applied only to root a noise"
            end
          else
            ::Noise.new frequencies: frequencies, offsets: offsets, child: sub
          end
        end
      end
    end
  end
end
