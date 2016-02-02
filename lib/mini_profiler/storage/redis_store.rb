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
        name = "#{@prefix}date" + DateTime.now.to_date.to_s
        redis.lpush(name,key)
        #slowest_paths= bottom(10)
        #slowest_paths_date_limits = bottom_date_limits(10, "2016-01-01", "2016-02-10")
      end

      def load(id)
        key = "#{@prefix}#{id}"
        raw = redis.get key
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

      def avg_duration(path)
        b= redis.lrange("#{path}",0,-1)
        sum =0.0
        b.each do |xid|
          profiling_data=Marshal::load(redis.get "#{@prefix}#{xid}")
          profiling_data =::JSON.parse(profiling_data.to_json)
          sum = sum + profiling_data["root"]["duration_milliseconds"]
        end
         sum = sum/b.length
      end

      def avg_duration_date_limits(path,startDate,endDate)
        #startDate and endDate arguments are strings
        startDate=startDate.split("-")
        endDate=endDate.split("-")
        b= redis.lrange("#{path}",0,-1)
        sum =0.0
        values = 0
        b.each do |xid|
          profiling_data=Marshal::load(redis.get "#{@prefix}#{xid}")
          profiling_data =::JSON.parse(profiling_data.to_json)
          profile_date=profiling_data["date_time"][0,10].split("-")
          if((profile_date[0].to_i.between?(startDate[0].to_i,endDate[0].to_i)) && (profile_date[1].to_i.between?(startDate[1].to_i,endDate[1].to_i)) && (profile_date[2].to_i.between?(startDate[2].to_i,endDate[2].to_i)))
              sum = sum + profiling_data["root"]["duration_milliseconds"]
              values = values +1
          end
        end
         sum = sum/values
      end

      def bottom(n)
        pathHash = Hash.new
        pathkeys = redis.keys('MPRedisStorepath*')
        pathkeys.each do |path|
          duration = avg_duration(path)
          pathHash["#{path}"] = duration
        end
          sorted_by_duration = pathHash.sort_by{|pathname,duration| -duration}.to_a
          sorted_by_duration[0..n-1]
      end

      def bottom_date_limits(n,startDate,endDate)
        pathHash = Hash.new
        pathkeys = redis.keys('MPRedisStorepath*')
        pathkeys.each do |path|
          duration = avg_duration_date_limits(path,startDate,endDate)
          pathHash["#{path}"] = duration
        end
        sorted_by_duration = pathHash.sort_by{|pathname,duration| -duration}.to_a
        sorted_by_duration[0..n]
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
