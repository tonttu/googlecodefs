require 'md5'
require 'fileutils'
require 'net/http'
require 'uri'

module CacheFetch
	@@cachedir = ''
	def self.cachedir=(value)
		@@cachedir = File.expand_path(value)
		FileUtils::mkdir_p File.join(@@cachedir, 'archives') unless File.exists? File.join(@@cachedir, 'archives')
	end
	def self.cachedir
		@@cachedir
	end

	def urlcache url
		File.join @@cachedir, MD5.new(url).to_s
	end

	def fetch_cache_to_file url
		hashpath = File.join @@cachedir, 'archives', MD5.new(url).to_s
		FileUtils::mkdir_p(hashpath) unless File.exists?(hashpath)
		
		return File.read(File.join(hashpath, '.filename')) if File.exists?(File.join(hashpath, '.filename'))

		res = nil

		STDERR.puts "Downloading #{url}"
		res = Net::HTTP.get_response(URI.parse(url))

		targetname = ''
		targetname = $1 if res['content-disposition'].to_s =~ /filename="(.*?)"/
		targetname = $& if targetname.empty? && url =~ /[^\/]+$/
		targetname = 'files' if targetname.empty?

		content = nil
		content = 'rar' if res['content-type'].to_s =~ /rar/

		targetname += ".#{content}" unless content.nil? || targetname =~ /#{content}$/
	
		filename = File.join hashpath, targetname

		File.open(File.join(hashpath, '.filename'), 'w') {|io| io.write(filename)}
		File.open(filename, 'w') do |io|
			io.write(res.body)
		end
		filename
	end

	def fetch_cache url
		hashfile = urlcache url
		if File.exists?(hashfile)
			STDERR.puts "Reading #{url} from cache"
			io = File.open(hashfile, 'r')
			res = Marshal.load(io)
			io.close
			res
		else
			STDERR.puts "Downloading #{url}"
			res = Net::HTTP.get_response(URI.parse(url))
			obj = block_given? ? yield(res) : res
			io = File.open(hashfile, 'w')
			Marshal.dump(obj, io)
			io.close
			obj
		end
	end
end
