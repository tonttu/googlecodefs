require 'md5'
require 'fileutils'
require 'net/http'
require 'uri'

module CacheFetch
	@@cachedir = ''
	def self.cachedir=(value)
		@@cachedir = File.expand_path(value)
		FileUtils::mkdir_p @@cachedir
	end
	def self.cachedir
		@@cachedir
	end

	def urlcache url
		File.join @@cachedir, MD5.new(url).to_s
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
