# frozen_string_literal: true

require "redis"
require "securerandom"

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

  ADD_PROCESS_SCRIPT = <<-LUA
    -- Parse arguments
    local sorted_set = ARGV[1]
    local process_id = ARGV[2]
    local limit = tonumber(ARGV[3])
    local ttl = tonumber(ARGV[4])
    local now = tonumber(ARGV[5])

    -- Get count of current processes. If more than the max, check if any of the processes have timed out
    -- and try again.
    local process_count = redis.call('zcard', sorted_set)
    if process_count >= limit then
      local max_score = now - ttl
      local expired_keys = redis.call('zremrangebyscore', sorted_set, '-inf', max_score)
      if expired_keys > 0 then
        process_count = redis.call('zcard', sorted_set)
      end
    end

    -- Success so add to the list and set a global expiration so the list cleans up after itself.
    if process_count < limit then
      redis.call('zadd', sorted_set, now, process_id)
      redis.call('pexpire', sorted_set, math.ceil(ttl * 1000))
    end

    -- Return the number of processes running before the process was added.
    return process_count
  LUA

  # This class level variable will be used to load the SHA1 of the script at runtime.
  @add_process_sha1 = nil

  # This error will be thrown when the throttle block can't be executed.
  class ThrottledError < StandardError
  end

  @redis = nil

  class << self
    # Either configure the redis instance using a block or yield the instance. Configuring with
    # a block allows you to use things like connection pools etc. without hard coding a single
    # instance.
    #
    # @param block [Proc] A block that returns a redis instance.
    # @return [Redis] The redis instance.
    # @example
    #   Restrainer.redis { redis_pool.instance }
    def redis(&block)
      if block
        @redis = block
      else
        unless @redis
          client = Redis.new
          @redis = lambda { client }
        end
        @redis.call
      end
    end

    # Set the redis instance to a specific instance. It is usually preferable to use
    # the block form for configurating the instance so that it can be evaluated at
    # runtime.
    #
    # @param conn [Redis]
    # @return [void]
    # @example
    #   Restrainer.redis = Redis.new
    def redis=(conn)
      @redis = lambda { conn }
    end
  end

  # Create a new restrainer. The name is used to identify the Restrainer and group
  # processes together. You can create any number of Restrainers with different names.
  #
  # The required limit parameter specifies the maximum number of processes that
  # will be allowed to execute the throttle block at any point in time.
  #
  # The timeout parameter is used for cleaning up internal data structures so that
  # jobs aren't orphaned if their process is killed. Processes will automatically
  # be removed from the running jobs list after the specified number of seconds.
  # Note that the Restrainer will not handle timing out any code itself. This
  # value is just used to insure the integrity of internal data structures.
  def initialize(name, limit:, timeout: 60, redis: nil)
    @name = name
    @limit = limit
    @timeout = timeout
    @key = "#{self.class.name}.#{name}"
    @redis = redis
  end

  # Wrap a block with this method to throttle concurrent execution. If more than the
  # alotted number of processes (as identified by the name) are currently executing,
  # then a Restrainer::ThrottledError will be raised.
  #
  # @param limit [Integer] The maximum number of processes that can be executing
  #   at any one time. Defaults to the value passed to the constructor.
  # @return [void]
  # @raise [Restrainer::ThrottledError] If the throttle would be exceeded.
  def throttle(limit: nil)
    limit ||= self.limit

    # limit of less zero is no limit; limit of zero is allow none
    return yield if limit < 0

    process_id = lock!(limit: limit)
    begin
      yield
    ensure
      release!(process_id)
    end
  end

  # Obtain a lock on one the allowed processes. The method returns a process
  # identifier that must be passed to the release! to release the lock.
  # You can pass in a unique identifier if you already have one.
  #
  # @param process_id [String] A unique identifier for the process. If none is
  #   passed, a unique value will be generated.
  # @param limit [Integer] The maximum number of processes that can be executing
  #   at any one time. Defaults to the value passed to the constructor.
  # @return [String] The process identifier.
  # @raise [Restrainer::ThrottledError] If the throttle would be exceeded.
  def lock!(process_id = nil, limit: nil)
    process_id ||= SecureRandom.uuid
    limit ||= self.limit

    # limit of less zero is no limit; limit of zero is allow none
    return nil if limit < 0
    raise ThrottledError.new("#{self.class}: #{@name} is not allowing any processing") if limit == 0

    add_process!(redis, process_id, limit)
    process_id
  end

  # Release one of the allowed processes. You must pass in a process id
  # returned by the lock method.
  #
  # @param process_id [String] The process identifier returned by the lock call.
  # @return [Boolean] True if the process was released, false if it was not found.
  def release!(process_id)
    return false if process_id.nil?

    remove_process!(redis, process_id)
  end

  # Get the number of processes currently being executed for this restrainer.
  #
  # @return [Integer] The number of processes currently being executed.
  def current
    redis.zcard(key).to_i
  end

  # Clear all locks.
  #
  # @return [void]
  def clear!
    redis.del(key)
  end

  private

  def redis
    @redis || self.class.redis
  end

  # Hash key in redis to story a sorted set of current processes.
  attr_reader :key

  # Add a process to the currently run set.
  def add_process!(redis, process_id, throttle_limit)
    process_count = eval_script(redis, process_id, throttle_limit)
    if process_count >= throttle_limit
      raise ThrottledError.new("#{self.class}: #{@name} already has #{process_count} processes running")
    end
  end

  # Remove a process to the currently run set. Returns true if the process was removed.
  def remove_process!(redis, process_id)
    result = redis.zrem(key, process_id)
    result = true if result == 1
    result
  end

  # Evaluate and execute a Lua script on the redis server.
  def eval_script(redis, process_id, throttle_limit)
    sha1 = @add_process_sha1
    if sha1.nil?
      sha1 = redis.script(:load, ADD_PROCESS_SCRIPT)
      @add_process_sha1 = sha1
    end

    begin
      redis.evalsha(sha1, [], [key, process_id, throttle_limit, @timeout, Time.now.to_f])
    rescue Redis::CommandError => e
      if e.message.include?("NOSCRIPT")
        sha1 = redis.script(:load, ADD_PROCESS_SCRIPT)
        @add_process_sha1 = sha1
        retry
      else
        raise e
      end
    end
  end
end
