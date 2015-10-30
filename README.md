This gem provides a method of throttling calls across processes that can be very useful if you have to call an external service with limited resources.

A [redis server](http://redis.io/) is required to use this gem.

### Usage

This code will throttle all calls to the mythical MyService so that no more than 100 calls are ever being made at a single time across all application processes.

```ruby
restrainer = Restrainer.new(:my_service, limit: 100)
restrainer.throttle do
  MyServiceClient.call
end
```

You can also override the limit in the `throttle` method. Setting a limit of zero will disable processing entirely. Setting a limit less than zero will remove the limit. Note that the limit set in the throttle is not shared with other processes, but the count of the number of processes is shared. Thus it is possible to have the throttle allow one process but reject another if the limits are different.

Instances of Restrainer do not use any internal state to keep track of number of running processes. All of that information is maintained in redis. Therefore you don't need to worry about maintaining references to Restrainer instances and you can create them as needed as long as they are named consistently. You can create multiple Restrainers for different uses in your application by simply giving them different names.

### Configuration

To set the redis connection used by for the gem you can either specify a block that yields a Redis::Client or explicitly set the attribute.

```ruby
Restrainer.redis{ connection_pool.redis }

Restrainer.redis = redis_client
```

### Internals

To protect against situations where a process is killed without a chance to cleanup after itself (i.e. `kill -9`), each process is only tracked for a limited amount of time (one minute by default). After this time, the Restrainer will assume that the process has been orphaned and removes it from the list.

The timeout can be set by the timeout option on the constructor. If you have any timeouts set on the services being called in the block, you should set the Restrainer timeout to a slightly higher value.

```ruby
restrainer = Restrainer.new(:my_service, 100, timeout: 10)
```