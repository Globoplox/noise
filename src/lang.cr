require "./noise"
# TODO: add debug info to tokens and parser output
# Cleanup errors
module Noise::Lang
  class AST
    enum Type
      NOISE
      SCALAR
    end

    abstract class Expression < AST
      abstract def expression_type : Type

      abstract def build : Float64 | ::Noise
    end

    class Unary < Expression
      def initialize(@operator : String, @right : Expression)
      end

      def expression_type : Type
        @right.type
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

      def expression_type : Type
        case {@left.type, @right.type}
        when {Type::Scalar, Type::Scalar} then Type::Scaler
        else Type::Noise
        end
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

      def expression_type : Type
        Type::SCALAR
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

      def expression_type : Type
        Type::NOISE
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

      def expression_type : Type
	      Type::NOISE
      end

      # Fallback to 4D for now, TODO: supports dimension wildcards parameters
      # This kind sucks
      def dimension_parameters_to_indexable(parameters : Array(Parameter))
        default = parameters.find &.dimension.nil?
        r = Array(Float64?).new(4, default.try &.value)
        parameters.each do |parameter|
          dim = parameter.dimension
          r[dim] = parameter.value if dim
        end
        r
      end

      # TODO: handle period. IDK how.
      def build : Float64 | ::Noise
        sub = @target.build
        case sub
        in Float64 then raise "Cannot apply noise parameters to a scalar value"
        in ::Noise
          frequencies = dimension_parameters_to_indexable @parameters.select(&.name.== "frequency")
          offsets = dimension_parameters_to_indexable @parameters.select(&.name.== "offset")
          ::Noise.new frequencies: frequencies, offsets: offsets, child: sub

          #if @parameters.any?(&.name.== "period")
          #  periods = dimension_parameters_to_indexable(@parameters.select(&.name.== "period")).map &.try &.to_u32
          #  ::Noise.new frequencies: frequencies, offsets: offsets, periods: periods
          #else
          #end
        end
      end
    end
  end

  module Lexer
    extend self
    
    STOPWORDS = ['+', '-', '*', '/', '[', ']', '(', ')']
    WHITESPACE = ['\n', '\t', '\r', ' ']
    
    def lex(io) : Array(String)
      tokens = [] of String
      buffer = [] of Char
      io.each_char do |c|
        if c.in? STOPWORDS
          if !buffer.empty?
            tokens << buffer.join
            buffer.clear
          end
          buffer << c
          tokens << buffer.join
          buffer.clear
        elsif c.in? WHITESPACE
          if !buffer.empty?
            tokens << buffer.join
            buffer.clear
          end
        else
          buffer << c
        end
      end
      tokens << buffer.join unless buffer.empty?
      tokens
    end
  end

  class Parser
    @tokens : Array(String)
    @cursor = 0

    def initialize(io)
      @tokens = Lexer.lex io
    end

    def parameter(name) : AST::Parameter
      list = (next_token || raise "Unexpected end of input").split ':'
      case list.size
      when 1 then AST::Parameter.new name, nil, list[0].to_f64
      when 2 then AST::Parameter.new name, parameter_dimension_alias(list[0]), list[1].to_f64
      else raise "Unexpected parameter value format #{list}"
      end
    end

    def parameter_dimension_alias(dimension : String?) : UInt32?
      case dimension 
      when nil then nil
      when "t", "x" then 0u32
      when "y" then 1u32
      when "z" then 2u32
      else dimension.to_u32
      end
    end
    
    def expression : AST::Expression
      elements = [] of AST::Expression | {binary: String} | {unary: String}
      last = nil
      loop do
        token = next_token

        case {token, last}
        when {")", :operator}, {nil, _}
          break
        when {"[", :operator}
          target = elements[-1].as AST::Expression
          parameters = [] of AST::Parameter
          loop do
            sub_token = next_token
            case sub_token
            when nil then raise "Unexpected end of input"
            when "]"
              break
            when "f", "freq", "frequency", "frequencies"
              parameters << parameter name: "frequency"
            when "o", "off", "offset", "offsets"
              parameters << parameter name: "offset"
            when "p", "period", "periods"
              parameters << parameter name: "period"
            else
              raise "Unexpected noise parameter name '#{sub_token}'"
            end
          end
          elements[-1] = AST::Parameters.new target, parameters
        when {"(", :unary}, {"(", :binary}, {"(", nil}
          elements << expression()
          last = :operator

        when {"/", :operator}, {"*", :operator}, {"+", :operator}, {"-", :operator}
          elements << {binary: token}
          last = :binary

        when {"+", :binary}, {"-", :binary}, {"+", :unary}, {"-", :unary}, {"+", nil}, {"-", nil}
          elements << {unary: token}
          last = :unary

        when {_, :unary}, {_, :binary}, {_, nil}
          if token.char_at(0).try &.ascii_number?
            elements << AST::Number.new token.to_f64
          else 
            elements << AST::Noise.new token
          end
          last = :operator
        else 
          raise "Parser exception: cannot parse token #{token.dump} after a #{last || "NOTHING"} token"
        end
      end

      raise "Unfinished Expression" if last.in? [:unary, :binary, nil]

      # Everything has left associatitvity
      priorities = [
        [{unary: "+"}, {unary: "-"}],
        [{binary: "*"}, {binary: "/"}],
        [{binary: "+"}, {binary: "-"}],
      ]

      
      priorities.each do |priority|
        loop do 
          found = elements.index &.in? priority
          break unless found
          element = elements[found]
          case element 
          in NamedTuple(binary: String)
            elements[found - 1, 3] = [AST::Binary.new(
              elements[found - 1].as AST::Expression,
              element[:binary], 
              elements[found + 1].as AST::Expression
            )]
          in NamedTuple(unary: String)
            elements[found, 2] = [AST::Unary.new(element[:unary], elements[found + 1].as AST::Expression)]
          in AST::Expression then raise "Expected operator, found '#{element}"
          end
        end
      end

      raise "Stray element in operation list: #{elements}" unless elements.size == 1

      elements.first.as AST::Expression
    end
    
    def next_token : String?
      @tokens[@cursor]?.try &.tap { @cursor += 1 }
    end
  end
end
