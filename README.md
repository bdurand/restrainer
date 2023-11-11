[![Continuous Integration](https://github.com/bdurand/restrainer/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/restrainer/actions/workflows/continuous_integration.yml)
[![Regression Test](https://github.com/bdurand/restrainer/actions/workflows/regression_test.yml/badge.svg)](https://github.com/bdurand/restrainer/actions/workflows/regression_test.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)

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

If the throttle is already full, the block will not be run and a `Restrainer::ThrottledError` will be raised.

You can also override the limit in the `throttle` method. Setting a limit of zero will disable processing entirely. Setting a limit less than zero will remove the limit. Note that the limit set in the throttle is not shared with other processes, but the count of the number of processes is shared. Thus it is possible to have the throttle allow one process but reject another if the limits are different.

You can also manually lock and release processes using the `lock` and `release` methods if your logic needs to break out of a block.

```ruby
  process_id = restrainer.lock!
  begin
    # Do something
  ensure
    restrainer.release!(process_id)
  end
```

If you already hava a unique identifier, you can pass it in to the lock! method. This can be useful if the calls to `lock!` and `release!` are in different parts of the code but have access to the same common identifier. Identifiers are unique per throttle name, so you can use something as simple as database row id.

Instances of Restrainer do not use any internal state to keep track of the number of running processes. All of that information is maintained in redis. Therefore you don't need to worry about maintaining references to Restrainer instances and you can create them as needed as long as they are named consistently. You can create multiple Restrainers for different uses in your application by simply giving them different names.

### Configuration

To set the redis connection used by for the gem you can either specify a block that yields a `Redis` object (from the [redis](https://github.com/redis/redis-rb) gem) or you can explicitly set the attribute. The block form is generally preferred since it can work with connection pools, etc.

```ruby
Restrainer.redis{ connection_pool.redis }

Restrainer.redis = redis_client
```

You can also pass in a `Redis` instance in the constructor.

```ruby
restrainer = Restrainer.new(limit: 5, redis: my_redis)
```

### Internals

To protect against situations where a process is killed without a chance to cleanup after itself (i.e. `kill -9`), each process is only tracked for a limited amount of time (one minute by default). After this time, the Restrainer will assume that the process has been orphaned and removes it from the list.

The timeout can be set by the timeout option on the constructor. If you have any timeouts set on the services being called in the block, you should set the Restrainer timeout to a slightly higher value.

```ruby
restrainer = Restrainer.new(:my_service, 100, timeout: 10)
```

This gem does clean up after itself nicely, so that it won't ever leave unused data lying around in redis.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'restrainer'
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install restrainer
```

## Contributing

Open a pull request on GitHub.

Please use the [standardrb](https://github.com/testdouble/standard) syntax and lint your code with `standardrb --fix` before submitting.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
