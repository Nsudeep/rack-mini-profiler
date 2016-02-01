module Rack
  class MiniProfiler
    class RedisStore < AbstractStore
      EXPIRES_IN_SECONDS = 60 * 60 * 24

      def initialize(args = nil)
        @args               = args || {}
        @prefix             = @args.delete(:prefix)     || 'MPRedisStore'
        @redis_connection   = @args.delete(:connection)
        @expires_in_seconds = @args.delete(:expires_in) || EXPIRES_IN_SECONDS
      end

      def save(page_struct)
        #setex is SET + EXPIRE
        redis.setex "#{@prefix}#{page_struct[:id]}", @expires_in_seconds, Marshal::dump(page_struct)

        name="#{@prefix}path#{page_struct[:name]}"
        key="#{page_struct[:id]}"
        redis.lpush(name,key)
      end

      def load(id)
        key = "#{@prefix}#{id}"
        raw = redis.get key
        #binding.pry
        begin
          Marshal::load(raw) if raw
        rescue
          # bad format, junk old data
          redis.del key
          nil
        end
      end

      def set_unviewed(user, id)
        key = "#{@prefix}-#{user}-v"
        redis.sadd key, id
        redis.expire key, @expires_in_seconds
      end

      def set_viewed(user, id)
        redis.srem "#{@prefix}-#{user}-v", id
      end

      def get_unviewed_ids(user)
        redis.smembers "#{@prefix}-#{user}-v"
      end

      def diagnostics(user)
"Redis prefix: #{@prefix}
Redis location: #{redis.client.host}:#{redis.client.port} db: #{redis.client.db}
unviewed_ids: #{get_unviewed_ids(user)}
"
      end

      def avg_duration(name)
        b= redis.lrange("#{@prefix}path#{name}",0,-1)
        sum =0.0
        b.each do |xid|
          profiling_data=Marshal::load(redis.get "#{@prefix}#{xid}")
          profiling_data =::JSON.parse(profiling_data.to_json)
          sum = sum + profiling_data["root"]["duration_milliseconds"]
        end
         sum = sum/b.length
      end

      def avg_duration(name,startDate,endDate)
        #startDate and endDate arguments are strings
        startDate=starteDate.split("-")
        endDate=endDate.split("-")
        b= redis.lrange("#{@prefix}path#{name}",0,-1)
        sum =0.0
        values = 0
        b.each do |xid|
          profiling_data=Marshal::load(redis.get "#{@prefix}#{xid}")
          profiling_data =::JSON.parse(profiling_data.to_json)
          profile_date=profiling_data["date_time"][0,10].split("-")
          if((profile_date[0].between(startDate[0],endDate[0])) && (profile_date[1].between(startDate[1],endDate[1])) && (profile_date[1].between(startDate[1],endDate[1])))
              sum = sum + profiling_data["root"]["duration_milliseconds"]
              values = values +1
          end

        end
         sum = sum/values
      end


      private

      def redis
        @redis_connection ||= begin
          require 'redis' unless defined? Redis
          Redis.new(@args)
        end
      end

    end
  end
end
