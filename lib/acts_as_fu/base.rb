%w(rubygems activerecord).each { |lib| require lib }

RAILS_ROOT = File.join(File.dirname(__FILE__), '..') unless defined?(RAILS_ROOT)
RAILS_ENV = 'test' unless defined?(RAILS_ENV)

module ActsAsFu

  class Connection < ActiveRecord::Base
    cattr_accessor :connected
    cattr_reader :log
    self.abstract_class = true

    def self.connect!(config={})
      @@log = ""
      self.logger = Logger.new(StringIO.new(log))
      self.connection.disconnect! rescue nil
      self.establish_connection(config)
    end
  end

  def build_model(name, options={}, &block)
    names = NamedBase.new(name)
    connect! unless connected?
    
    super_class = options[:superclass] || begin
      ActsAsFu::Connection.connection.create_table(names.table_name, :force => true) { }
      ActsAsFu::Connection
    end

    set_class!(names, super_class, &block)
  end

  private

  def set_class!(names, super_class, &block)
    Object.send(:remove_const, names.class_name) rescue nil

    klass = Class.new(super_class)
    set_class_constant(names, klass)
    model_eval(klass, names, &block)
    # require 'rubygems'
    # require 'ruby-debug'
    # debugger
    
    klass
  end
  
  def set_class_constant(names, klass)
    if names.class_nesting_depth == 0
      Object.const_set(names.class_name, klass)
    else
      namespaced_module = names.class_nesting.constantize
      namespaced_module.const_set(names.class_name_without_nesting, klass)
    end
  end

  def connect!
    ActsAsFu::Connection.connect!({
      :adapter => "sqlite3",
      :database => ":memory:"
    })
    ActsAsFu::Connection.connected = true
  end

  def connected?
    ActsAsFu::Connection.connected
  end

  def model_eval(klass, names, &block)
    @@names = names
    class << klass
      def method_missing_with_columns(sym, *args, &block)
        ActsAsFu::Connection.connection.change_table(@@names.table_name) do |t|
          t.send(sym, *args)
        end
      end
    
      alias_method_chain :method_missing, :columns
    end

    klass.class_eval(&block) if block_given?

    class << klass
      alias_method :method_missing, :method_missing_without_columns
    end
  end
  
  # Below all pinched from Rails::Generator::NamedBase to be consistent with the inflections used in generators
  class NamedBase
    
    attr_reader   :name, :class_name, :singular_name, :plural_name, :table_name
    attr_reader   :class_path, :file_path, :class_nesting, :class_nesting_depth, :class_name_without_nesting
    
    def initialize(name)
      assign_names!(name.to_s.singularize)
    end
    
    def assign_names!(name)
      @name = name
      base_name, @class_path, @file_path, @class_nesting, @class_nesting_depth = extract_modules(@name)
      @class_name_without_nesting, @singular_name, @plural_name = inflect_names(base_name)
      @table_name = (!defined?(ActiveRecord::Base) || ActiveRecord::Base.pluralize_table_names) ? plural_name : singular_name
      @table_name.gsub! '/', '_'
      if @class_nesting.empty?
        @class_name = @class_name_without_nesting
      else
        @table_name = @class_nesting.underscore << "_" << @table_name
        @class_name = "#{@class_nesting}::#{@class_name_without_nesting}"
      end
    end

    # Extract modules from filesystem-style or ruby-style path:
    #   good/fun/stuff
    #   Good::Fun::Stuff
    # produce the same results.
    def extract_modules(name)
      modules = name.include?('/') ? name.split('/') : name.split('::')
      name    = modules.pop
      path    = modules.map { |m| m.underscore }
      file_path = (path + [name.underscore]).join('/')
      nesting = modules.map { |m| m.camelize }.join('::')
      [name, path, file_path, nesting, modules.size]
    end

    def inflect_names(name)
      camel  = name.camelize
      under  = camel.underscore
      plural = under.pluralize
      [camel, under, plural]
    end
  end
end
