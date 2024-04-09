require "../noise"
require "./ast"

module Noise::Lang

  class Parser
 
    @tokens : Array(String)
    @cursor = 0

    def initialize(io)
      @tokens = Parser.lex io
    end

    STOPWORDS = ['+', '-', '*', '/', '[', ']', '(', ')']
    WHITESPACE = ['\n', '\t', '\r', ' ']

    # Naive tokenizer
    def self.lex(io) : Array(String)
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

    # Parse an expression
    # Naive recursive descent state machine parser:
    # It first  extract all operators and operands in order
    # Then reduce them following operator priorities.
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
