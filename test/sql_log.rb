module SqlSource
  class << self
    attr_accessor :current_tag
    attr_accessor :dest, :bc

    def find_source(trace)
      return @bc.clean(trace)[-1]
    end

    def find_spec(trace)
      index = trace.rindex { |x|
        x.include? "_test.rb"
      }
      return nil if index.nil?
      return trace[index].scan(/(?:.*\/)(.*?\w*?_test\.rb:[0-9]*)/)[0][0]
    end

    def register_sql(trace, sql)
      source = self.find_source(trace)
      spec = self.find_spec(trace)
      return unless (not source.nil? and not sql.nil? and not spec.nil?)
      tag = "#{source} !!! #{spec}"
      if tag != @current_tag
        if not @current_tag.nil?
          @dest.puts("-#@current_tag")
        end
        @dest.puts("+#{tag}")
        @current_tag = tag
      end
      @dest.puts("|>#{sql}")
    end

    def close()
      return unless not @current_tag.nil?
      @dest.puts("-#@current_tag")
      @dest.close
    end
  end
end

SqlSource.dest = File.new(Rails.root.join("sql.logs"), "a")
SqlSource.bc = ActiveSupport::BacktraceCleaner.new
SqlSource.bc.add_filter { |line| line.gsub(Rails.root.to_s, '') }
SqlSource.bc.add_silencer { |line| line =~ /\.rvm|_test/ }

END {
  SqlSource.close
}

ActiveSupport::Notifications.subscribe "sql.active_record" do |*args|
  event = ActiveSupport::Notifications::Event.new *args

  unless event.payload[:cached]
    SqlSource.register_sql(caller, event.payload[:sql])
  end
end
