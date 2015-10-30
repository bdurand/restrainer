require 'redis'
require 'securerandom'

# Redis backed throttling mechanism to ensure that only a limited number of processes can
# be executed at any one time.
#
# Usage:
#   Restrainer.new(:foo, 10).throttle do
#     # Do something
#   end
#
# If more than the specified number of processes as identified by the name argument is currently
# running, then the throttle block will raise an error.
class Restrainer
  
  attr_reader :name, :limit
  
  class ThrottledError < StandardError
  end
  
  class << self
    # Either configure the redis instance using a block or yield the instance. Configuring with
    # a block allows you to use things like connection pools etc. without hard coding a single
    # instance.
    #
    # Example: `Restrainer.redis{ redis_pool.instance }
    def redis(&block)
      if block
        @redis = block
      elsif defined?(@redis) && @redis
        @redis.call
      else
        raise "#{self.class.name}.redis not configured"
      end
    end
    
    # Set the redis instance to a specific instance. It is usually preferable to use the block
    # form for configurating the instance.
    def redis=(conn)
      @redis = lambda{ conn }
    end
  end
  
  # Create a new restrainer. The name is used to identify the Restrainer and group processes together.
  # You can create any number of Restrainers with different names. The limit parameter specifies
  # the maximum number of processes that will be allowed to execute the throttle block at any point in time.
  #
  # The timeout parameter is used for cleaning up internal data structures so that jobs aren't orphaned 
  # if their process is killed. Processes will automatically be removed from the running jobs list after the
  # specified number of seconds. Note that the Restrainer will not handle timing out any code itself. This
  # value is just used to insure the integrity of internal data structures.
  def initialize(name, limit: -1, timeout: 60)
    @name = name
    @limit = limit
    @timeout = timeout
    @key = "#{self.class.name}.#{name.to_s}"
  end
  
  # Wrap a block with this method to throttle concurrent execution. If more than the alotted number
  # of processes (as identified by the name) are currently executing, then a Restrainer::ThrottledError
  # will be raised.
  #
  # The limit argument can be used to override the limit set in the constructor. A limit of
  def throttle(limit = nil)
    limit ||= self.limit
    
    # limit of less zero is no limit; limit of zero is allow none
    return yield if limit < 0
    raise ThrottledError.new("#{self.class}: #{@name} is not allowing any processing") if limit == 0
    
    # Grab a reference to the redis instance to that it will be consistent throughout the method
    redis = self.class.redis
    check_running_count!(redis, limit)
    process_id = SecureRandom.uuid
    begin
      add_process!(redis, process_id)
      yield
    ensure
      remove_process!(redis, process_id)
    end
  end
  
  # Get the number of processes currently being executed for this restrainer.
  def current(redis = nil)
    redis ||= self.class.redis
    redis.zcard(key).to_i
  end
  
  private
  
  # Hash key in redis to story a sorted set of current processes.
  def key
    @key
  end
  
  # Raise an error if there are too many running processes.
  def check_running_count!(redis, limit)
    running_count = current(redis)
    if running_count >= limit
      running_count = current(redis) if cleanup!(redis)
      if running_count >= limit
        raise ThrottledError.new("#{self.class}: #{@name} already has #{running_count} processes running")
      end
    end
  end
  
  # Add a process to the currently run set.
  def add_process!(redis, process_id)
    redis.multi do |conn|
      conn.zadd(key, Time.now.to_i, process_id)
      conn.expire(key, @timeout)
    end
  end
  
  # Remove a process to the currently run set.
  def remove_process!(redis, process_id)
    redis.zrem(key, process_id)
  end
  
  # Protect against kill -9 which can cause processes to not be removed from the lists.
  # Processes will be assumed to have finished by a specified timeout (in seconds).
  def cleanup!(redis)
    max_score = Time.now.to_i - @timeout
    expired = redis.zremrangebyscore(key, "-inf", max_score)
    expired > 0 ? true : false
  end
  
end
