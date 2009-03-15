require File.dirname(__FILE__) + "/common"

require 'quix/ruby'

root = Pathname(__FILE__).dirname + ".."
file = root + "README"
lib = root + "lib"

describe file do
  ["Synopsis", "Raw Form"].each do |section|
    it "#{section} should run as claimed" do
      contents = file.read
      code = (
        "$LOAD_PATH.unshift '#{lib.expand_path}'\n" +
        contents.match(%r!== #{section}.*?\n(.*?)^==!m)[1]
      )
      expected = code.scan(%r!\# => (.*?)\n!).flatten.join("\n")
      pipe_to_ruby(code).chomp.should == expected
    end
  end
end
