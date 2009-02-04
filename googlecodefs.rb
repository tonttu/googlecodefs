#!/usr/bin/env ruby
SOFTNAME="Google Code FileSystem 1.0-rc1"
# http://github.com/tonttu/googlecodefs
# © Riku Palomäki 2007, email: 'evxh@cnybznxv.sv'.tr('a-z','n-za-m')
#
# With GoogleCodeFS you can use google code search for sourcecode as if
# it was a filesystem. It uses fuse and it's ruby bindings.


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
end

class GCommon
	attr_accessor :date, :parent
	attr_reader :name

	def executable?; false end

	def name=(value)
#		puts "FOOBAR!"
		GIndexer.unset getpath if @name
		
		tmp, i = value.dup, 0
		while GIndexer.get(@parent.getpath + value)
			value = tmp + '.' + i.to_s
			i += 1
		end if @parent
		
		@name = value
		GIndexer.set getpath, self
	end

	def initialize attrs
		@name = nil
		@date = attrs[:date] ? attrs[:date] : Time.now
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

class GArchiveFile < GFile
	include CacheFetch
	def executable?; true end
	def contents
		@filename ||= fetch_cache_to_file @url
		olddir = FileUtils::pwd
		FileUtils::cd File.dirname(@filename)

		unless File.exists?(@file)
			system 'unp', File.basename(@filename), '--', @file
		end
		io = "READ ERROR\n"
		io = File.read(@file)	if File.exists?(@file)
		FileUtils::cd olddir
		io
	end

	def initialize attrs
		@url = attrs[:url]
		@file = attrs[:file]
		super(attrs)
	end
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

class GArchiveDir < GDir
	include CacheFetch
	def files
		@real_files ||= []
		@filename ||= fetch_cache_to_file @url
		if @real_files.empty?
			olddir = FileUtils::pwd
			dir = File.dirname(@filename)
			FileUtils::cd dir

			unless File.exists?('.unpacked')
				system 'unp', File.basename(@filename)
				if $?.success?
					FileUtils.touch('.unpacked')
				end
			end
			FileUtils::cd olddir
			@real_files = Dir.entries(File.join(dir, @path))
			@real_files.each do |x|
				next if x == '.' || x == '..' || x == '.filename' || x == '.unpacked'
				if File.directory?(File.join(dir, @path, x))
					GArchiveDir.new :name => x, :path => @path + [x], :url => @url,
						:parent => self, :date => @date
				else
					GArchiveFile.new :name => x, :file => File.join(@path + [x]), :url => @url,
						:parent => self, :date => @date
				end
			end
		end
		@files
	end

	def initialize attrs
		@path = attrs[:path] ? attrs[:path] : []
		@url = attrs[:url]
		@file = attrs[:file]
		super(attrs)
	end
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
		GFile.new :parent => @root, :name => 'README', :contents =>
"This is a readme file for #{SOFTNAME}
  * search for something: cd <searchterms>
"
	end

	def contents(path)
		puts "contents(#{path})"
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
			list.each do |date, name, files, download|
				puts "SUB: #{File.basename(name)}"
				p2 = GDir.new :parent => p, :name => File.basename(name), :date => date
				GArchiveDir.new :parent => p2, :name => File.basename(download), :date => date, :url => download, :path => []
				GArchiveFile.new :parent => p2, :name => File.basename(name), :date => date, :url => download, :file => name
				files.each do |n, v|
					GFile.new :parent => p2, :name => n, :contents => v, :date => date
				end
			end
			p.files.collect{|x| x.name }
		end
	end

	def executable?(path)
		GIndexer.get(path) ? GIndexer.get(path).executable? : false
	end

	def size(path)
		tmp = GIndexer.get(path)
		tmp && tmp.file? && !tmp.is_a?(GArchiveFile) ? tmp.contents.to_s.length : 0
	end

	def directory?(path)
		GIndexer.get(path) ? GIndexer.get(path).directory? : scan_path(path).length == 1
	end

	def can_write?(path); true end
	def can_delete?(path); true end
	def can_mkdir?(path); true end

	def write_to(path, str)
		tmp = GIndexer.get path
		if tmp
			tmp.contents = str
		else
			tmp = GIndexer.get File.dirname(path)
			GFile.new :name => File.basename(path), :contents => str, :parent => tmp if tmp
		end
	end

	def delete(path)
		tmp = GIndexer.get path
		if tmp
			tmp.parent.files.delete(tmp)
			GIndexer.unset path
		end
	end

	def can_rmdir?(path)
		tmp = GIndexer.get path
		tmp && tmp.files.empty?
	end

	def rmdir(path)
		tmp = GIndexer.get path
		if tmp
			tmp.parent.files.delete(tmp)
			GIndexer.unset path
		end
	end

	def mkdir(path)
		return if GIndexer.get path
		tmp = GIndexer.get File.dirname(path)
		GDir.new :name => File.basename(path), :parent => tmp if tmp
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
