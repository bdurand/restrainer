# frozen_string_literal: true

require_relative "spec_helper"

describe Restrainer do
  before(:each) do
    Restrainer.new(:restrainer_test, limit: 1).clear!
  end

  it "should have a name and max_processes" do
    restrainer = Restrainer.new(:restrainer_test, limit: 1)
    expect(restrainer.name).to eq(:restrainer_test)
    expect(restrainer.limit).to eq(1)
  end

  it "should run a block!" do
    restrainer = Restrainer.new(:restrainer_test, limit: 1)
    x = nil
    expect(restrainer.throttle { x = restrainer.current }).to eq(1)
    expect(x).to eq(1)
    expect(restrainer.current).to eq(0)
  end

  it "should throw an error if too many processes are already running" do
    restrainer = Restrainer.new(:restrainer_test, limit: 5)
    x = nil
    restrainer.throttle do
      restrainer.throttle do
        restrainer.throttle do
          restrainer.throttle do
            restrainer.throttle do
              expect { restrainer.throttle { x = 1 } }.to raise_error(Restrainer::ThrottledError)
            end
          end
        end
      end
    end
    expect(x).to eq(nil)
  end

  it "should not throw an error if the number of processes is under the limit" do
    restrainer = Restrainer.new(:restrainer_test, limit: 2)
    x = nil
    restrainer.throttle do
      restrainer.throttle { x = 1 }
    end
    expect(x).to eq(1)
  end

  it "should let the throttle method override the limit" do
    restrainer = Restrainer.new(:restrainer_test, limit: 1)
    x = nil
    restrainer.throttle do
      restrainer.throttle(limit: 2) { x = 1 }
    end
    expect(x).to eq(1)
  end

  it "should allow processing to be turned off entirely by setting the limit to zero" do
    restrainer = Restrainer.new(:restrainer_test, limit: 1)
    x = nil
    expect { restrainer.throttle(limit: 0) { x = 1 } }.to raise_error(Restrainer::ThrottledError)
    expect(x).to eq(nil)
  end

  it "should allow the throttle to be opened up entirely with a negative limit" do
    restrainer = Restrainer.new(:restrainer_test, limit: 0)
    x = nil
    restrainer.throttle(limit: -1) { x = 1 }
    expect(x).to eq(1)
  end

  it "should cleanup the running process list if orphaned processes exist" do
    restrainer = Restrainer.new(:restrainer_test, limit: 1, timeout: 10.1234)
    key = restrainer.send(:key)
    Restrainer.redis.zadd(key, Time.now.to_f - 11, "orphaned_process")
    x = nil
    restrainer.throttle { x = 1 }
    expect(x).to eq(1)
    expect(Restrainer.redis.zscore(key, "orphaned_process")).to eq(nil)
  end

  it "should be able to lock! and release! processes manually" do
    restrainer = Restrainer.new(:restrainer_test, limit: 5)
    p1 = restrainer.lock!
    begin
      p2 = restrainer.lock!
      begin
        p3 = restrainer.lock!
        begin
          p4 = restrainer.lock!
          begin
            p5 = restrainer.lock!
            begin
              expect { restrainer.lock! }.to raise_error(Restrainer::ThrottledError)
            ensure
              restrainer.release!(p5)
            end
            p6 = restrainer.lock!
            restrainer.release!(p6)
          ensure
            restrainer.release!(p4)
          end
        ensure
          restrainer.release!(p3)
        end
      ensure
        restrainer.release!(p2)
      end
    ensure
      restrainer.release!(p1)
    end
  end

  it "should be able to pass in the process id" do
    restrainer = Restrainer.new(:restrainer_test, limit: 1)
    expect(restrainer.lock!("foo")).to eq "foo"
  end

  it "should not get a lock! if the limit is 0" do
    restrainer = Restrainer.new(:restrainer_test, limit: 0)
    expect { restrainer.lock! }.to raise_error(Restrainer::ThrottledError)
  end

  it "should get a lock! if the limit is negative" do
    restrainer = Restrainer.new(:restrainer_test, limit: -1)
    process_id = restrainer.lock!
    expect(process_id).to eq nil
    restrainer.release!(nil)
  end

  it "should be able to override the limit in lock!" do
    restrainer = Restrainer.new(:restrainer_test, limit: 0)
    restrainer.lock!(limit: 1)
  end

  it "should return true from release! when the process was locked and false when it was not" do
    restrainer = Restrainer.new(:restrainer_test, limit: 1)
    process_id = restrainer.lock!
    expect(restrainer.release!(process_id)).to eq true
    expect(restrainer.release!(process_id)).to eq false
    expect(restrainer.release!("nonexistent")).to eq false
  end

  it "should reload the script if it has been flushed from the script cache" do
    restrainer = Restrainer.new(:restrainer_test, limit: 1)
    Restrainer.redis.script(:flush)
    x = nil
    restrainer.throttle { x = 1 }
    expect(x).to eq(1)
  end
end
