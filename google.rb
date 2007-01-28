require 'cache_fetch.rb'
require 'xml/dom/builder'
require 'time'
require 'cgi'

class GoogleCodeAPI
	include CacheFetch
	def url search
		"http://www.google.com/codesearch/feeds/search?q=#{URI.escape(search)}"
	end
	def entries q
		fetch_cache url(q) do |res|
			doc = XML::DOM::Builder.new.parse(res.body)
			doc.childNodes[0].childNodes.to_a.find_all{|x| x.nodeName == 'entry'}.collect do |entry|
				entry.childNodes.to_a.inject(Hash.new) {|hash, node| hash[node.nodeName] = node; hash }
			end
		end
	end
	def search q
		entries(q).collect do |entry|
			d = entry['updated'] ? Time.parse(entry["updated"].firstChild.to_s) : Time.now
			files = {}
			files['title'] = entry["title"].firstChild.to_s if entry['title']
			files['match'] = entry['gcs:match'] ? CGI.unescapeHTML(entry["gcs:match"].firstChild.to_s) : ''
			files['match'].gsub!(/<\/?(pre|b)>/, '')
			files['matchline'] = entry["gcs:match"].getAttribute('lineNumber').to_s if entry['gcs:match']
			files['author'] = entry["author"].firstChild.firstChild.to_s if entry['author'] && entry['author'].firstChild.firstChild
			files['rights'] = entry["rights"].firstChild.to_s if entry['rights']
			files['filename'] = entry["gcs:file"].getAttribute('name').to_s if entry['gcs:file']
			files['searchurl'] = entry["link"].getAttribute('href').to_s if entry['link']
			files['downloadurl'] = entry["gcs:package"].getAttribute('uri').to_s if entry['gcs:package']

			fn, dl = files['filename'].dup, files['downloadurl'].dup
			files.keys.each {|x| files[x] += "\n"}
#			res[:updated] = Time.parse(entry["updated"].firstChild.to_s)
			[d, fn, files, dl]
		end
	end

=begin
gcs:match(lineNumber="57", type="text/html")
  "<pre>#define <b>malloc</b>(x) PR_<b>Malloc</b>(x)\n</pre>"
gcs:file(name="apache_1.3.37/src/lib/expat-lite/xmldef.h")
title(type="text")
  "apache_1.3.37/src/lib/expat-lite/xmldef.h"
author()
  name()
    "Code owned by external author."
rights()
  "Apache"
id()
  "http://www.google.com/codesearch?hl=en&q=+malloc+show:PN_jTmOQfT4:IvRjWPH8El8:YuxTMEPie1Q&sa=N&ct=rx&cd=1&cs_p=http://mirrors.ccs.neu.edu/Apache/dist/httpd/apache_1.3.37.tar.gz&cs_f=apache_1.3.37/src/lib/expat-lite/xmldef.h&cs_p=http://mirrors.ccs.neu.edu/Apache/dist/httpd/apache_1.3.37.tar.gz&cs_f=apache_1.3.37/src/lib/expat-lite/xmldef.h#a0"
gcs:package(name="http://mirrors.ccs.neu.edu/Apache/dist/httpd/apache_1.3.37.tar.gz", uri="http://mirrors.ccs.neu.edu/Apache/dist/httpd/apache_1.3.37.tar.gz")
link(href="http://www.google.com/codesearch?hl=en&amp;q=+malloc+show:PN_jTmOQfT4:IvRjWPH8El8:YuxTMEPie1Q&amp;sa=N&amp;ct=rx&amp;cd=1&amp;cs_p=http://mirrors.ccs.neu.edu/Apache/dist/httpd/apache_1.3.37.tar.gz&amp;cs_f=apache_1.3.37/src/lib/expat-lite/xmldef.h&amp;cs_p=http://mirrors.ccs.neu.edu/Apache/dist/httpd/apache_1.3.37.tar.gz&amp;cs_f=apache_1.3.37/src/lib/expat-lite/xmldef.h#a0", rel="alternate", type="text/html")
updated()
  "2007-01-28T06:41:23Z"
=end
end
