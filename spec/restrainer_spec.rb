require 'spec_helper'

describe Restrainer do
  
  it "should have a name and max_processes" do
    restrainer = Restrainer.new(:restrainer_test, limit: 1)
    expect(restrainer.name).to eq(:restrainer_test)
    expect(restrainer.limit).to eq(1)
  end
  
  it "should run a block" do
    restrainer = Restrainer.new(:restrainer_test, limit: 1)
    x = nil
    expect(restrainer.throttle{ x = restrainer.current }).to eq(1)
    expect(x).to eq(1)
    expect(restrainer.current).to eq(0)
  end
  
  it "should throw an error if too many processes are already running" do
    restrainer = Restrainer.new(:restrainer_test, limit: 1)
    x = nil
    restrainer.throttle do
      expect(lambda{restrainer.throttle{ x = 1 }}).to raise_error(Restrainer::ThrottledError)
    end
    expect(x).to eq(nil)
  end
  
  it "should not throw an error if the number of processes is under the limit" do
    restrainer = Restrainer.new(:restrainer_test, limit: 2)
    x = nil
    restrainer.throttle do
      restrainer.throttle{ x = 1 }
    end
    expect(x).to eq(1)
  end
  
  it "should let the throttle method override the limit" do
    restrainer = Restrainer.new(:restrainer_test, limit: 1)
    x = nil
    restrainer.throttle do
      restrainer.throttle(limit: 2){ x = 1 }
    end
    expect(x).to eq(1)
  end
  
  it "should allow processing to be turned off entirely by setting the limit to zero" do
    restrainer = Restrainer.new(:restrainer_test, limit: 1)
    x = nil
    expect(lambda{restrainer.throttle(limit: 0){ x = 1 }}).to raise_error(Restrainer::ThrottledError)
    expect(x).to eq(nil)
  end
  
  it "should allow the throttle to be opened up entirely with a negative limit" do
    restrainer = Restrainer.new(:restrainer_test, limit: 0)
    x = nil
    restrainer.throttle(limit: -1){ x = 1 }
    expect(x).to eq(1)
  end
  
  it "should cleanup the running process list if orphaned processes exist" do
    restrainer = Restrainer.new(:restrainer_test, limit: 1, timeout: 10)
    x = nil
    restrainer.throttle do
      Timecop.travel(11) do
        restrainer.throttle{ x = 1 }
      end
    end
    expect(x).to eq(1)
  end
end
