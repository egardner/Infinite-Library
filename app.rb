require 'sinatra'
require 'haml'
require 'json'
require 'sass'
require 'octokit'
require 'awesome_print'
require 'httparty'
require 'nokogiri'

#===============================================================================
## Setup
secrets = './secrets.rb'
require secrets if File.file? secrets
ENV['CLIENT_ID']     ||= ''
ENV['CLIENT_SECRET'] ||= ''

configure do
  set :scss, :style => :compressed, :debug_info => false
end

#===============================================================================
## Routes

get '/css/:name.css' do |name|
  content_type :css
  scss "sass/#{name}".to_sym, :layout => false
end

get '/' do
  @message = "Welcome to the Infinite Library"
  haml :index, :layout => :default_layout
end

get '/search' do
  client = Octokit::Client.new(
    :client_id => ENV['CLIENT_ID'], 
    :client_secret => ENV['CLIENT_SECRET'])
  book    = params['book']
  user    = client.user('GITenberg')
  results = client.search_repositories "#{book} user:#{user.name}"

  @found_books  = []
  @message      = 'Sorry, no results found.'
  @colors       = ['bg-navy', 'bg-blue', 'bg-teal', 'bg-olive', 'bg-green', 
   		   'bg-yellow', 'bg-red', 'bg-orange', 'bg-maroon', 'bg-purple']

  if results.items.length > 0
    results.items.each do |repo|
      book = process_repo_contents(repo)
      unless book[:files].length < 1 
        @found_books << book
      end
    end
    puts @found_books
    @message = "Found #{@found_books.length} results."
  end

  haml :results, :layout => :default_layout
end


get '/book/:repo' do
  client = Octokit::Client.new(
    :client_id => ENV['CLIENT_ID'], 
    :client_secret => ENV['CLIENT_SECRET'])
  user   = client.user("GITenberg")
  repo   = client.repository("#{user.name}/#{params['repo']}")

  @book     = process_repo_contents(repo)
  @contents = ""

  if @book[:files][:txt]
    text = HTTParty.get(@book[:files][:txt])
    @contents = text.gsub("\n", "<br />")
  end

  if @book[:files][:html]
    html = Nokogiri::HTML(HTTParty.get(@book[:files][:html]))
    @contents = html.css("body").to_html
  end

  haml :contents, :layout => :default_layout
end

#===============================================================================
## Methods

#===============================================================================
# Humanize String method
# Cleans up GITenberg book titles into something more human-friendly
# Returns a string
# Not 100% there just yet.
#===============================================================================
def humanize_string(ugly_string)
  ugly_string
    .split('_')[0]
    .split('--')[0]
    .gsub('-', ' ')
    .split(/(?<!^)(?=[A-Z])/)
    .join(' ')
end

#===============================================================================
# Process Repo Contents method
# Accepts a Sawywer::Resource object for a single Github repo
# Returns a book hash full of data from repo's contents
#===============================================================================
def process_repo_contents(repo)
  # Initialize Octokit client
  client = Octokit::Client.new(
    :client_id => ENV['CLIENT_ID'], 
    :client_secret => ENV['CLIENT_SECRET'])

  user = client.user('GITenberg')
  
  book = {
    :repo   => repo.name,
    :name   => humanize_string(repo.name),
    :id     => repo.name.split('_')[-1],
    :desc   => repo.description,
    :files  => {},
    :cover  => ''
  }
 
  # Check for subtitle
  unless repo.name.index('--').nil?
    subtitle = repo.name.split('_')[0].split('--')[-1].gsub('-', ' ')
    book.store(:subtitle, subtitle)
  end

  # Loop through repo contents to find book files
  # Check repo size first: very small but non-zero values for "size" attr
  # seem to indicate that the repository is empty. Not sure if there is a
  # better way to check for this with Github's api.
  # Attempting to call .contents on a repo without contents throws an error.
  unless repo.size < 50
    client.contents(repo.full_name).each do |item|
      # Asciidoc
      if item.name.downcase == ( book[:name] + ".asciidoc" ).downcase
        book[:files].store(:asciidoc, item.download_url)
      end
      # HTML (lives in a subfolder)
      if item.name.downcase == book[:id] + "-h" && item.type == "dir"
        raw_url = 
          "https://raw.githubusercontent.com/" +
          "#{user.name}/#{repo.name}/master/" +
          "#{book[:id]}-h/#{book[:id]}-h.htm"
        book[:files].store(:html, raw_url)
      end
      # Text version
      if item.name.downcase == ( book[:id] + ".txt" ).downcase
        book[:files].store(:txt, item.download_url)
      end
      # Cover image, if one exists
      if item.name.downcase == ( "cover.jpg" )
        book[:cover] = item.download_url
      end
    end
  end
 

  return book
end



