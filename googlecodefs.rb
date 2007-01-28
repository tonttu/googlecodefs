# Google Code FileSystem 1.0-rc1
# http://www.hyperteksti.net/projects/googlecodefs
# © Riku Palomäki 2007, email: 'evxh@cnybznxv.sv'.tr('a-z','n-za-m')
#
# With GoogleCodeFS you can search for google for sourcecode as if
# it was a filesystem. It uses fuse and it's ruby bindings.
#
# Example session:
# ~$ mount google
# ~$ cd google
# ~/google$ cd foo
# ~/google/foo$ ls

dir = ARGV[0].to_s
if !File.directory?(dir)
	puts "Usage: #{$0} directory"
	exit
end

require 'fusefs'
require 'google.rb'

CacheFetch.cachedir = File.join ENV['HOME'], '.googlecodefs-cache'

class GIndexer
	@@index = {}
	def self.get name
		@@index[name.sub(/\/$/, '')]
	end
	def self.set name, value
		@@index[name.sub(/\/$/, '')] = value
#		puts @@index.inspect
	end
	def self.unset name
		@@index.delete name.sub(/\/$/, '') if @@index.has_key?(name.sub(/\/$/, ''))
	end
	def self.debug
		puts @@index.keys
	end
end

class GCommon
	attr_accessor :date, :parent
	attr_reader :name

	def name=(value)
#		puts "FOOBAR!"
		GIndexer.unset getpath if @name
		@name = value
		GIndexer.set getpath, self
	end

	def initialize attrs
		@name = nil
		@date = attrs[:date]
		@parent = attrs[:parent]
		@parent.files << self if @parent
		self.name = attrs[:name]
	end

	def getpath
		@parent.getpath + @name
	end
end

class GFile < GCommon
	attr_accessor :contents

	def initialize attrs
		@contents = attrs[:contents]
		super attrs
	end
	def directory?; false end
	def file?; true end
end

class GDir < GCommon
	attr_accessor :files

	def initialize attrs
		@files = attrs[:files] ? attrs[:files] : []
		super attrs
	end

	def getpath
		@parent.getpath + @name + '/'
	end
	def directory?; true end
	def file?; false end
end

class GRoot < GDir
	def getpath
		'/'
	end
	def directory?; true end
	def file?; false end
end

class GoogleDir < FuseFS::FuseDir
	@@root = nil
	def self.run dir
		@@root = self.new
		FuseFS.set_root @@root
		FuseFS.mount_under dir
		FuseFS.run
	end

	def initialize
		@api = GoogleCodeAPI.new
		@root = GRoot.new :name => ''
		GFile.new :parent => @root, :name => 'README', :contents => "This is a readme file\n"
	end

	def contents(path)
		puts "contents(#{path})"
		GIndexer.debug
		if GIndexer.get path
			GIndexer.get(path).files.collect{|x| x.name }
		else
			scanned = scan_path(path)
			name = scanned.pop
			parent = GIndexer.get('/' + scanned.join('/'))
			puts "scanned: #{scanned.inspect}, name: #{name}"
			return if !parent || parent.file?
			#puts parent.inspect
			p = GDir.new :parent => parent, :name => name
		
			list = @api.search(name)
			list.each do |date, name, files|
				puts "SUB: #{name}"
				p2 = GDir.new :parent => p, :name => name, :date => date
				files.each do |n, v|
					GFile.new :parent => p2, :name => n, :contents => v, :date => date
				end
			end
			p.files.collect{|x| x.name }
		end
	end

	def directory?(path)
		if GIndexer.get path
			GIndexer.get(path).directory?
		else
			true
		end
	end

	def file?(path)
		if GIndexer.get path
			GIndexer.get(path).file?
		else
			false
		end
	end

	def read_file(path)
		if GIndexer.get path
			GIndexer.get(path).contents
		else
			nil
		end
	end
end

GoogleDir.run dir
