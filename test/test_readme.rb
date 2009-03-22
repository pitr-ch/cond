require File.dirname(__FILE__) + "/common"

require 'quix/ruby'

root = Pathname(__FILE__).dirname + ".."
file = root + "README"
lib = root + "lib"

describe file do
  ["Synopsis",
   "Raw Form",
   "Another Example",
   "Synopsis 2.0",
  ].each { |section|
    it "#{section} should run as claimed" do
      contents = file.read

      code = %{
        $LOAD_PATH.unshift "#{lib.expand_path}"
        require 'cond'
        include Cond
      } + contents.match(%r!== #{section}.*?\n(.*?)^\S!m)[1]

      expected = code.scan(%r!\# => (.*?)\n!).flatten.join("\n")
      pipe_to_ruby(code).chomp.should == expected
    end
  }
end
