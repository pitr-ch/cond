require File.dirname(__FILE__) + "/common"

include Cond

[:handling, :restartable].each { |keyword|
  describe "leave arguments" do
    it "should be passed to the #{keyword} block result (none)" do
      send(keyword) do
        leave
      end.should == nil
    end
    it "should be passed to the #{keyword} block result (single)" do
      send(keyword) do
        leave 3
      end.should == 3
    end
    it "should be passed to the #{keyword} block result (multiple)" do
      send(keyword) do
        leave 4, 5
      end.should == [4, 5]
    end
    it "should be passed to the #{keyword} block result (single array)" do
      send(keyword) do
        leave([6, 7])
      end.should == [6, 7]
    end
  end
}

[:handling, :restartable].each { |keyword|
  describe "again arguments" do
    before :each do
      @memo = []
    end
    it "should be passed to the #{keyword} block args (none)" do
      send(keyword) do |*args|
        @memo.push :visit
        if @memo.size == 2
          args.should == []
          again
        elsif @memo.size == 3
          args.should == []
          leave
        end
        again
      end
    end
    it "should be passed to the #{keyword} block args (single)" do
      send(keyword) do |*args|
        @memo.push :visit
        if @memo.size == 2
          args.should == [3]
          again
        elsif @memo.size == 3
          args.should == []
          leave
        end
        again 3
      end
    end
    it "should be passed to the #{keyword} block args (multiple)" do
      send(keyword) do |*args|
        @memo.push :visit
        if @memo.size == 2
          args.should == [4, 5]
          again
        elsif @memo.size == 3
          args.should == []
          leave
        end
        again 4, 5
      end
    end
    it "should be passed to the #{keyword} block args (single array)" do
      send(keyword) do |*args|
        @memo.push :visit
        if @memo.size == 2
          args.should == [6, 7]
          again
        elsif @memo.size == 3
          args.should == []
          leave
        end
        again [6, 7]
      end
    end
  end
}
