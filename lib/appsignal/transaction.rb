module Appsignal
  class Transaction

    def self.create(key, env)
      Thread.current[:appsignal_transaction_id] = key
      Appsignal.transactions[key] = Appsignal::Transaction.new(key, env)
    end

    def self.current
      Appsignal.transactions[Thread.current[:appsignal_transaction_id]]
    end

    attr_reader :id, :events, :exception, :env, :log_entry

    def initialize(id, env)
      @id = id
      @events = []
      @log_entry = nil
      @exception = nil
      @env = env
    end

    def request
      ActionDispatch::Request.new(@env)
    end

    def set_log_entry(event)
      @log_entry = event
    end

    def add_event(event)
      @events << event
    end

    def add_exception(ex)
      @exception = ex
    end

    def exception?
      !! @exception
    end

    def formatted_exception
      return {} unless exception?
      {
        :backtrace => @exception.backtrace,
        :exception => @exception.name,
        :message => @exception.message
      }
    end

    def formatted_events
      @events.map do |event|
        {
          :name => event.name,
          :duration => event.duration,
          :time => event.time,
          :end => event.end,
          :payload => sanitized_event_payload(event)
        }
      end
    end

    def sanitized_event_payload(event)
      Appsignal.event_payload_sanitizer.call(event)
    end

    def formatted_log_entry
      {
        :name => request.fullpath,
        :environment => Rails.env,
        :server => @env['SERVER_NAME'],
        :kind => 'http_request'
      }.merge(formatted_payload)
    end

    def formatted_payload
      if @log_entry
        {
          :duration => @log_entry.duration,
          :time => @log_entry.time,
          :end => @log_entry.end
        }.merge(sanitized_event_payload(@log_entry)).tap do |o|
          o[:action] = "#{@log_entry.payload[:controller]}"\
            "##{@log_entry.payload[:action]}"
        end
      else
        if exception?
          {:action => @exception.inspect.gsub(/^<#(.*)>$/, '\1')}
        else
          {}
        end
      end
    end

    def to_hash
      {
        :request_id => @id,
        :log_entry => formatted_log_entry,
        :events => formatted_events,
        :exception => formatted_exception,
        :failed => exception.present?
      }
    end

    def complete!
      Thread.current[:appsignal_transaction_id] = nil
      current_transaction = Appsignal.transactions.delete(@id)
      if @events.any? || exception?
        Appsignal.agent.add_to_queue(current_transaction.to_hash)
      end
    end

  end
end