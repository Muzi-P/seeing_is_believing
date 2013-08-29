require 'seeing_is_believing/line'
require 'seeing_is_believing/has_exception'

class SeeingIsBelieving
  class Result
    include HasException
    include Enumerable

    attr_accessor :stdout, :stderr, :exitstatus, :bug_in_sib, :number_of_captures

    alias bug_in_sib? bug_in_sib

    def has_stdout?
      stdout && !stdout.empty?
    end

    def has_stderr?
      stderr && !stderr.empty?
    end

    def record_result(line_number, value)
      if    results_for(line_number).size <  number_of_captures then results_for(line_number) << value.inspect
      elsif results_for(line_number).size == number_of_captures then results_for(line_number) << '...'
      end
      value
    end

    def record_exception(line_number, exception)
      recorded_exception = RecordedException.new exception.class.name,
                                                 exception.message,
                                                 exception.backtrace
      self.exception = recorded_exception
      results_for(line_number).exception = recorded_exception
    end

    def [](line_number)
      results_for(line_number)
    end

    def each(&block)
      max = results.keys.max || 1
      (1..max).each { |line_number| block.call self[line_number] }
    end

    def inspect
      results
      "#<SIB::Result #{
        instance_variables.map { |name| "#{name}=#{instance_variable_get(name).inspect}" }.join("\n  ")
      }>"
    end

    def number_of_captures
      @number_of_captures || Float::INFINITY
    end

    private

    def results_for(line_number)
      results[line_number] ||= Line.new
    end

    def results
      @results ||= Hash.new
    end
  end
end
