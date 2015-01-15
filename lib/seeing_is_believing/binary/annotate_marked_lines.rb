# encoding: utf-8
require 'seeing_is_believing/code'

class SeeingIsBelieving
  module Binary
    # Based on the behaviour of xmpfilger (a binary in the rcodetools gem)
    class AnnotateMarkedLines
      def self.prepare_body(uncleaned_body, markers)
        require 'seeing_is_believing/binary/remove_annotations'
        RemoveAnnotations.call uncleaned_body, false, markers
      end

      def self.expression_wrapper(markers)
        lambda do |program, filename, max_line_captures|
          inspect_linenos = []
          pp_linenos      = []
          value_regex     = markers[:value][:regex]
          Code.new(program).inline_comments.each do |c|
            next unless c.text[value_regex]
            c.whitespace_col == 0 ? pp_linenos      << c.line_number - 1
                                  : inspect_linenos << c.line_number
          end

          require 'seeing_is_believing/rewrite_code'
          RewriteCode.call \
            program,
            filename,
            max_line_captures,
            before_all: -> {
              # TODO: this is duplicated with the InspectExpressions class
              max_line_captures_as_str = max_line_captures.inspect
              max_line_captures_as_str = 'Float::INFINITY' if max_line_captures == Float::INFINITY
              "require 'pp'; $SiB.record_filename #{filename.inspect}; $SiB.record_max_line_captures #{max_line_captures_as_str}; $SiB.record_num_lines #{program.lines.count}; "
            },
            after_each: -> line_number {
              # 74 b/c pretty print_defaults to 79 (guessing 80 chars with 1 reserved for newline), and
              # 79 - "# => ".length # => 4
              should_inspect = inspect_linenos.include?(line_number)
              should_pp      = pp_linenos.include?(line_number)
              inspect        = "$SiB.record_result(:inspect, #{line_number}, v)"
              pp             = "$SiB.record_result(:pp, #{line_number}, v) { PP.pp v, '', 74 }"

              if    should_inspect && should_pp then ").tap { |v| #{inspect}; #{pp} }"
              elsif should_inspect              then ").tap { |v| #{inspect} }"
              elsif should_pp                   then ").tap { |v| #{pp} }"
              else                                   ")"
              end
            }
        end
      end

      def self.call(body, results, options)
        new(body, results, options).call
      end

      def initialize(body, results, options={})
        @options = options
        @body    = body
        @results = results
      end

      # TODO:
      # I think that this should respect the alignment strategy
      # and we should just add a new alignment strategy for default xmpfilter style
      def call
        @new_body ||= begin
          require 'seeing_is_believing/binary/rewrite_comments'
          require 'seeing_is_believing/binary/format_comment'
          include_lines = []

          if @results.has_exception?
            exception_result  = sprintf "%s: %s", @results.exception.class_name, @results.exception.message.gsub("\n", '\n')
            exception_lineno  = @results.exception.line_number
            include_lines << exception_lineno
          end

          new_body = RewriteComments.call @body, include_lines: include_lines do |comment|
            exception_on_line  = exception_lineno == comment.line_number
            annotate_this_line = comment.text[value_regex]
            pp_annotation      = annotate_this_line && comment.whitespace_col.zero?
            normal_annotation  = annotate_this_line && !pp_annotation
            if exception_on_line && annotate_this_line
              [comment.whitespace, FormatComment.call(comment.text_col, value_prefix, exception_result, @options)]
            elsif exception_on_line
              whitespace = comment.whitespace
              whitespace = " " if whitespace.empty?
              [whitespace, FormatComment.call(0, exception_prefix, exception_result, @options)]
            elsif normal_annotation
              result = @results[comment.line_number].map { |result| result.gsub "\n", '\n' }.join(', ')
              [comment.whitespace, FormatComment.call(comment.text_col, value_prefix, result, @options)]
            elsif pp_annotation
              result = @results[comment.line_number-1, :pp].map { |result| result.chomp }.join("\n,") # ["1\n2", "1\n2", ...
              swap_leading_whitespace_in_multiline_comment(result)
              comment_lines = result.each_line.map.with_index do |comment_line, result_offest|
                if result_offest == 0
                  FormatComment.call(comment.whitespace_col, value_prefix, comment_line.chomp, @options)
                else
                  leading_whitespace = " " * comment.text_col
                  leading_whitespace << FormatComment.call(comment.whitespace_col, nextline_prefix, comment_line.chomp, @options)
                end
              end
              comment_lines = [value_prefix.rstrip] if comment_lines.empty?
              [comment.whitespace, comment_lines.join("\n")]
            else
              [comment.whitespace, comment.text]
            end
          end

          require 'seeing_is_believing/binary/annotate_end_of_file'
          AnnotateEndOfFile.add_stdout_stderr_and_exceptions_to new_body, @results, @options

          new_body
        end
      end

      def value_prefix
        @value_prefix ||= @options[:markers][:value][:prefix]
      end

      def nextline_prefix
        @nextline_prefix ||= ('#' + ' '*value_prefix.size.pred)
      end

      def exception_prefix
        @exception_prefix ||= @options[:markers][:exception][:prefix]
      end

      def value_regex
        @value_regex ||= @options[:markers][:value][:regex]
      end

      def swap_leading_whitespace_in_multiline_comment(comment)
        return if comment.lines.size < 2
        return if comment[0] =~ /\S/
        nonbreaking_space = " "
        comment[0] = nonbreaking_space
      end
    end
  end
end
