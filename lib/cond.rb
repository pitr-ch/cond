
require 'cond/thread_local'
require 'cond/stack'
require 'cond/loop_with'
require 'cond/generator'
require 'cond/defaults'

# 
# Condition system for handling errors in Ruby.  See README.
# 
module Cond
  module_function

  #
  # Register a set of handlers.  The given hash is merged with the
  # set of current handlers.
  #
  # When the block exits, the previous set of handlers (if any) are
  # restored.
  #
  # Example:
  #
  #   handlers = {
  #     #
  #     # We are able to handle Fred errors immediately; no need to unwind
  #     # the stack.
  #     #
  #     FredError => lambda { |exception|
  #       # ...
  #       puts "Handled a FredError. Continuing..."
  #     },
  #   
  #     #
  #     # We want to be informed of Wilma errors, but we can't handle them.
  #     #
  #     WilmaError => lambda { |exception|
  #       puts "Got a WilmaError. Re-raising..."
  #       raise
  #     },
  #   }
  #
  #   Cond.with_handlers(handlers) {
  #     # ...
  #   }
  #
  def with_handlers(handlers)
    Cond.handlers_stack.push(Cond.handlers_stack.top.merge(handlers))
    begin
      yield
    ensure
      Cond.handlers_stack.pop
    end
  end
  
  #
  # Register a set of restarts.  The given hash is merged with the
  # set of current restarts.
  #
  # When the block exits, the previous set of restarts (if any) are
  # restored.
  #
  # Example:
  #
  #   Cond.with_restarts(:return_nil => lambda { return nil }) {
  #     # ..
  #   }
  #
  def with_restarts(restarts)
    Cond.restarts_stack.push(Cond.restarts_stack.top.merge(restarts))
    begin
      yield
    ensure
      Cond.restarts_stack.pop
    end
  end
    
  #
  # A default handler is provided which runs a simple input loop when
  # an exception is raised.
  #
  def with_default_handlers
    with_handlers(Cond.default_handlers) {
      yield
    }
  end

  #
  # Some default restarts are provided.
  #
  def with_default_restarts
    with_restarts(Cond.default_restarts) {
      yield
    }
  end

  #
  # Registers the default handlers and default restarts, and adds a
  # restart to leave the input loop.
  #
  def debugger
    restarts = {
      :leave_debugger => Restart.new("Leave debugger") {
        throw :leave_debugger
      }
    }
    catch(:leave_debugger) {
      with_default_handlers {
        with_default_restarts {
          with_restarts(restarts) {
            yield
          }
        }
      }
    }
  end

  #
  # The current set of restarts which have been registered.
  #
  def available_restarts
    Cond.restarts_stack.top
  end
    
  #
  # Find a restart by name.
  #
  def find_restart(name)
    available_restarts[name]
  end

  #
  # Call a restart from a handler; optionally pass it some arguments.
  #
  def invoke_restart(name, *args, &block)
    available_restarts.fetch(name) {
      raise(
        NoRestartError,
        "Did not find `#{name.inspect}' in available restarts"
      )
    }.call(*args, &block)
  end

  #
  # Find the closest-matching handler for the given Exception.
  #
  def find_handler(target)
    Cond.handlers_stack.top.fetch(target) {
      found = Cond.handlers_stack.top.inject(Array.new) { |acc, (klass, func)|
        index = target.ancestors.index(klass)
        if index
          acc << [index, func]
        else
          acc
        end
      }.sort_by { |t| t.first }.first
      found and found[1]
    }
  end

  ######################################################################
  # Restart and Handler 

  #
  # Base class for Restart and Handler.
  #
  class MessageProc < Proc
    def initialize(message = "", &block)
      @message = message
    end

    def message
      @message
    end
  end

  #
  # A restart.  Use of this is optional: you could just pass lambdas
  # to with_restarts, but you'll miss the description string shown
  # inside Cond#default_handler.
  #
  class Restart < MessageProc
  end

  #
  # A handler.  Use of this is optional: you could just pass lambdas
  # to with_handlers, but you'll miss the description string shown by
  # whichever tools might use it (currently none).
  #
  class Handler < MessageProc
  end

  ######################################################################
  # wrapping

  #
  # Allow handlers to be called from C code by wrapping a method with
  # begin/rescue.  Returns the aliased name of the original method.
  #
  # See the README.
  #
  # Example:
  #
  #   Cond.wrap_instance_method(Fixnum, :/)
  #
  def wrap_instance_method(mod, method)
    original = "cond_original_#{mod.inspect}_#{method.inspect}"
    # TODO: jettison 1.8.6, remove eval and use |&block|
    mod.module_eval %{
      alias_method :'#{original}', :'#{method}'
      def #{method}(*args, &block)
        begin
          send(:'#{original}', *args, &block)
        rescue Exception => e
          raise e
        end
      end
    }
    original
  end

  #
  # Allow handlers to be called from C code by wrapping a method with
  # begin/rescue.  Returns the aliased name of the original method.
  #
  # See the README.
  #
  # Example:
  #
  #   Cond.wrap_singleton_method(IO, :read)
  #
  def wrap_singleton_method(mod, method)
    singleton_class = class << mod ; self ; end
    wrap_instance_method(singleton_class, method)
  end

  ######################################################################
  # errors
  
  #
  # Cond.invoke_restart was called with an unknown restart.
  #
  class NoRestartError < StandardError
  end

  ######################################################################
  # singleton class

  class << self
    stack_0  = lambda { |*| Stack.new }
    stack_1  = lambda { |*| Stack.new.push(Hash.new) }
    defaults = lambda { |name| Defaults.send(name) }
    {
      :code_section_stack => stack_0,
      :exception_stack    => stack_0,
      :handlers_stack     => stack_1,
      :restarts_stack     => stack_1,
      :stream             => defaults,
      :default_handlers   => defaults,
      :default_restarts   => defaults,
    }.each_pair { |name, init|
      include ThreadLocal.accessor_module(name) {
        init.call(name)
      }
    }
  end

  ######################################################################
  # shiny exterior

  #
  # Similar to +return+ for the current +restartable+ or +handling+
  # section.
  #
  # Optionally pass arguments which will be the value returned by the
  # +restartable+ or +handling+ block.
  #
  # It has the semantics of +return+.  When given multiple arguments,
  # it returns an array.  When given one argument, it returns only
  # that argument (not an array).
  #
  def leave(*args)
    Cond.code_section_stack.top.leave(*args)
  end

  #
  # Run the +restartable+ or +handling+ block again.  This is called
  # from inside handlers and restarts.
  #
  # Optionally pass arguments which are given to the block.
  #
  def again(*args)
    Cond.code_section_stack.top.again(*args)
  end

  #
  # While inside a +restartable+ section, define a restart.
  # While inside a +handling+ section, define a handler.
  #
  def on(symbol, message = "", &block)
    Cond.code_section_stack.top.on(symbol, message, &block)
  end

  #
  # Begin a restartable section of code.
  #
  def restartable(&block)
    section = RestartableSection.new(&block)
    Cond.code_section_stack.push(section)
    begin
      section.instance_eval { run }
    ensure
      Cond.code_section_stack.pop
    end
  end
  
  #
  # Begin a section of code in which exceptions may be handled without
  # unwinding the stack.
  #
  def handling(&block)
    section = HandlingSection.new(&block)
    Cond.code_section_stack.push(section)
    begin
      section.instance_eval { run }
    ensure
      Cond.code_section_stack.pop
    end
  end

  class CodeSection  #:nodoc:
    include LoopWith
    include Generator

    def initialize(with_functions, &block)
      @with_functions = with_functions
      @block = block
      @leave, @again = (1..2).map { gensym }
    end

    def again(*args)
      throw @again
    end

    def leave(*args)
      case args.size
      when 0
        throw @leave
      when 1
        throw @leave, args.first
      else
        throw @leave, args
      end
    end

    def run
      loop_with(@leave, @again) {
        Cond.send(@with_functions, Hash.new) {
          throw @leave, @block.call
        }
      }
    end
  end

  class RestartableSection < CodeSection  #:nodoc:
    def initialize(&block)
      super(:with_restarts, &block)
    end

    def on(sym, message, &block)
      Cond.restarts_stack.top[sym] = Restart.new(message, &block)
    end
  end

  class HandlingSection < CodeSection  #:nodoc:
    def initialize(&block)
      super(:with_handlers, &block)
    end

    def on(sym, message, &block)
      Cond.handlers_stack.top[sym] = Handler.new(message, &block)
    end
  end

  ######################################################################
  # original raise

  define_method :original_raise, &method(:raise)
  module_function :original_raise
end

module Kernel
  remove_method :raise
  def raise(*args)
    if Cond.exception_stack.top
      # we are inside a handler
      if args.empty?
        Cond.original_raise(Cond.exception_stack.top)
      else
        Cond.original_raise(*args)
      end
    else
      # not inside a handler
      begin
        Cond.original_raise(*args)
      rescue Exception => exception
      end
      handler = Cond.find_handler(exception.class)
      if handler
        Cond.exception_stack.push(exception)
        begin
          handler.call(exception)
        ensure
          Cond.exception_stack.pop
        end
      else
        Cond.original_raise(exception)
      end
    end
  end
  remove_method :fail
  alias_method :fail, :raise
end
