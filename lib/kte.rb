# Economist2EPUB Scraper Script
require 'rubygems'
require 'bundler/setup'
require 'date'
require 'erb'
require 'fileutils'
require 'mechanize'
require 'mini_magick'
require 'open-uri'
require 'optparse'
require 'pony'
require 'progressbar'
require 'psych'
require 'zip/zip'
require 'zip/zipfilesystem'



class Issue
  attr_reader :sections
  attr_accessor :id,
                :title,
                :date,
                :publisher,
                :publication,
                :cover_image

  def initialize(id, publication, title, date=nil)
    @id = id
    @publication = publication
    @title = title
    begin
      @date = date || Date.parse(id)
    rescue
      @date = Date.today
    end
    @sections = []
  end

  def to_s
    @id + ": " + @title
  end

  def <<(section)
    @sections << section
  end

  def articles
    articles = []
    @sections.each { |s|
      s.articles.each { |a|
        articles << a } }
    articles
  end

  def images
    images = []
    articles.each { |a|
      a.images.each { |i|
        images << i } }
    images << cover_image
    images
  end

  def title_with_publication
    publication + " (Issue " + date.to_s + "): " + @title
  end
end

class Section
  attr_reader :articles
  attr_accessor :title

  def initialize(title)
    @title = title
    @articles = []
  end

  def <<(article)
    @articles << article
  end
end

# The Article class represents an article belonging to
# an issue
class Article
  attr_accessor :id,
                :title,
                :topic,
                :abstract,
                :uri,
                :content,
                :images

  def initialize(id, title, href)
    @id = "article" + id
    @title = title
    @uri = URI.parse(href)
    @images = []
  end

  def title_with_topic
    s = @title
    if (@topic && @topic != "")
      s = @topic + ": " +s
    end
    s
  end

  def to_s
    title_with_topic
  end
end

# The Image class represents an image embedded in an article
class Image
  attr_reader :id,
              :name,
              :uri,
              :rel_path,
              :content_type

  def initialize(href, name=nil)
    @uri = URI.parse(href)
    @name = name ? name : File.basename(File.basename(@uri.path))
    @rel_path = Image.rel_path_prefix + @name
    @content_type = guess_content_type(@uri.path)
    @id = "image" + @name.tr('._', '')
  end

  # derives a content type from the file extension
  def guess_content_type(path)
    content_type = ""
    if path.end_with?(".gif")
      content_type = "image/gif"
    elsif path.end_with?(".jpg")
      content_type = "image/jpeg"
    elsif path.end_with?(".png")
      content_type = "image/png"
    elsif path.end_with?(".svg")
      content_type = "image/svg+xml"
    end
    content_type
  end

  def self.rel_path_prefix
    "images/"
  end
end

# Scraper downloading
class EconomistScraper
  def initialize(config)
    @credentials = config['credentials']
    @agent = Mechanize.new
    @login_success = false
  end

  # Logs into the economist website with given credentials
  def login
    print "Logging in... "
    login_page = @agent.get "https://www.economist.com/user/login"
    login_form = login_page.form_with(:id => "user-login")
    login_form["name"] = @credentials['email']
    login_form["pass"] = @credentials['password']
    user_page = @agent.submit login_form

    # we check for the email address on the page.
    #If not present, we assume login failed
    @login_success = user_page.body.include?(@credentials['email'])
    if (@login_success)
      print "success\n"
    else
      print "error\nPlease check you credentials"
    end
    @login_success
  end

  # Scrapes the current issue
  def get_current_issue
    cover_page = @agent.get "http://www.economist.com/printedition"
    get_issue_from_cover_page(cover_page)
  end

  # Scrapes a specific issue by date (format YYYY-MM-DD)
  def get_issue(date)
    cover_page = @agent.get "http://www.economist.com/printedition/"+date
    get_issue_from_cover_page(cover_page)
  end

  private

  # Scrapes the issue from economist.com, starting with a
  # given cover page
  def get_issue_from_cover_page(cover_page)
    unless @login_success
      login
    end
    cover_image = cover_page.at(".issue-image > img")
    issue_id = id_from_href(cover_page.uri.path)
    issue = Issue.new(issue_id, "The Economist" ,cover_image['title'])
    issue.publisher = "The Economist Newspaper Ltd."
    issue.cover_image = Image.new(cover_image['src'], "cover.jpg")

    puts "Creating Kindle version of Issue " + issue.to_s
    puts ""
    article_ids = []
    cover_page.search(".section").each do |s_element|
      section = Section.new(s_element.at("h4").inner_html)
      s_element.search(".article").each do |a_element|
        link = a_element.at(".node-link")
        href = link["href"]
        title = link.text
        article = Article.new(id_from_href(href), title, href)
        article_ids << id_from_href(href)
        section << article
      end
      issue << section
    end

    puts "Downloading and processing articles:"
    STDOUT.flush
    all_articles = issue.articles
    progress = ProgressBar.new("Downloading", all_articles.length)
    all_articles.each_with_index do |article, done|

      article_page = @agent.get article.uri.to_s

        # get topic of article (its hard easier to extract than from the cover page)
      topic = article_page.at(".fly-title").text

        # the article abstract (curiously marked up as h1)
      if article_page.at("h1.rubric")
        article.abstract = article_page.at(".rubric").text
      end

        # now the article content
      c_element = article_page.at(".ec-article-content")

        # lets get rid of the related items box
      c_element.search(".related-items").remove

        # lets get rid of the related items box
      c_element.search(".related-expanded").remove

        # replace links with local references
      c_element.search("a").each do |a|
        if a['href'] && a['href'].start_with?("http://www.economist.com/node/") &&
            article_ids.include?(id_from_href(a['href']))
          a["href"] = a["href"].gsub("http://www.economist.com/node/", "") + ".html"
        end
      end

      c_element.search("p").each do |p|
        if p.children.first && p.children.first.name == "strong"
          p.swap("<h4>"+p.children.first.text+"</h4>")
        end
      end

        # download the article images
      images = c_element.search("img")
      images.each do |img|
        image = Image.new(img["src"])
        img["src"] = image.rel_path
        article.images << image
      end

      article.content = c_element.inner_html
      article.topic = topic if topic.strip != ""
      progress.inc
    end
    progress.finish
    puts ''
    issue
  end

  # Get the article id from its url
  def id_from_href(href)
    if href.include?("?")
      href = href.partition("?")[0]
    end
    id = href.split("/").last
    id
  end
end

class EpubWriter
  def initialize(config)
    @dirs = {
      :bin => File.join("..", "bin"),
      :templates => File.join("..", "templates")
    }
    if config['directories']
      @dirs[:issues] = config['directories']['issues'] || File.join("..", "issues"),
      @dirs[:tmp_base] = config['directories']['tmp'] || File.join("..", "tmp")
    end
  end

  # Starts the epub/mobi creation process
  def write(issue)
    @issue = issue
    @dirs[:tmp]      = File.join(@dirs[:tmp_base], issue.id)
    @dirs[:content]  = File.join(@dirs[:tmp], "OEBPS")
    @dirs[:images]   = File.join(@dirs[:tmp], "OEBPS", Image.rel_path_prefix)
    @dirs[:meta_inf] = File.join(@dirs[:tmp], "META-INF")
    @files = [
        { :template => "container.xml.erb", :path => File.join(@dirs[:meta_inf], "container.xml") },
        { :template => "content.opf.erb",   :path => File.join(@dirs[:content], "content.opf") },
        { :template => "toc.html.erb",      :path => File.join(@dirs[:content], "toc.html") },
        { :template => "toc.ncx.erb",       :path => File.join(@dirs[:content], "toc.ncx") },
        { :template => "style.css.erb", :path => File.join(@dirs[:content], "style.css") }
    ]
    @epub = File.join(@dirs[:issues], @issue.id)+'.epub'
    @mobi = File.join(@dirs[:issues], @issue.id)+'.mobi'

    make_dirs
    download_images
    write_articles
    write_meta_files
    zipIt
    convert_to_mobi

    if File.exists?(@mobi)
      @mobi
    else
      @epub
    end
  end

  private
  # Creates the directories to save the generated files
  def make_dirs
    FileUtils.rm_rf @dirs[:tmp]
    @dirs.each do |k, dir|
      FileUtils.mkdir_p dir
    end
  end

  # Returns the path where an article will be saved
  def article_path(article)
    article.id + ".html"
  end

  # Returns the path where an image will be saved
  def image_path(image)
    image.rel_path
  end

  # Write out article html files
  def write_articles
    puts "Converting articles to EPUB:"
    STDOUT.flush
    progress = ProgressBar.new("Converting", @issue.articles.length)
    @issue.articles.each do |article|
      if !article.content
        next
      end
      template = ERB.new(File.new(File.join(@dirs[:templates], "article.html.erb")).read, nil, "%")
      output_file = File.new(File.join(@dirs[:content], article_path(article)), "w+")
      output_file.write(template.result(binding))
      output_file.close
      progress.inc
    end
    progress.finish
    puts ''
  end

  # Download images embedded in articles of this issue
  def download_images
    puts "Downloading and processing images:"
    STDOUT.flush
    images = @issue.images
    progress = ProgressBar.new("Downloading", images.length)
    images.each do |i|
      download_image(i)
      progress.inc
    end
    progress.finish
    puts ''
  end

  # Write out all the meta files for the epub format
  def write_meta_files
    @files.each do |file|
      template = ERB.new(
          File.new(File.join(@dirs[:templates],file[:template])).read,
          nil, "%")
      output_file = File.new(file[:path], "w+")
      output_file.write(template.result(binding))
      output_file.close
    end
  end

  # Download and preprocess an image
  def download_image(image)
    dir = File.join(@dirs[:content], image.rel_path)
    img = MiniMagick::Image.open(image.uri.to_s)
    img.combine_options(:mogrify) do |c|
      c.type "optimize"
      c.colorspace "Gray"
      c.quality 60
      c.resize '450x550>'
    end
    img.write dir
  end

  # Compress the files to a epub file
  def zipIt
    puts "Creating EPUB package:"
    STDOUT.flush
    path = @dirs[:tmp]
    FileUtils.rm @epub, :force=>true
    Zip::ZipFile.open(@epub, 'w') do |zipfile|
      progress = ProgressBar.new("Compressing", Dir["#{path}/**/**"].length)
      Dir["#{path}/**/**"].each do |file|
        zipfile.add(file.sub(path+'/', ''), file)
        progress.inc
      end
      progress.finish
      puts ''
    end
  end

  # Convert the epub file to a mobi file with kindlegen
  def convert_to_mobi
    print "Converting to Kindle format... "
    kindlegen = 'kindlegen'
    if (RUBY_PLATFORM.downcase.include?("mswin"))
      kindlegen = kindlegen+".exe"
    end
    kindlegen = File.join(@dirs[:bin], kindlegen)
    # skip mobi creation if kindlegen can not be found
    if File.exists?(kindlegen)
      output = `#{kindlegen} #{@epub} -c2`
      if File.exists?(@mobi)
        puts "done"
      else
        puts "failed"
        puts output
      end

    else
      puts "skipped"
      puts "The program kindlegen was not found. Please obtain the kindlegen executable from Amazon."
    end
  end
end

class PostMan
  def initialize(config)
    if config['smtp']
      @smtp_config = {}
      config['smtp'].each {|k,v| @smtp_config[k.to_sym] = v}
      if @smtp_config[:authentication]
        @smtp_config[:authentication] = @smtp_config[:authentication].to_sym
      end
    end
    @to = config['deliver_to'].join(', ')
  end

  def send(issue, file)
    print "Delivering issue to " + @to + "..."
    filename = "document" + File.extname(file)
    if @smtp_config
      Pony.mail(:to => @to,
                :via => :smtp,
                :via_options => @smtp_config,
                :attachments => {filename => File.binread(file)}
      )
      puts "done"
    end
  end
end


class KindleTheEconomist

  def initialize
    @config = Psych::parse_file(File.join('..', 'config.yml')).to_ruby
    @scraper = EconomistScraper.new(@config)
    @writer = EpubWriter.new(@config)
    @postman = PostMan.new(@config)
  end


  def main
    if ARGV.length > 0
      ARGV.each do |arg|
        process_issue(@scraper.get_issue(arg))
      end
    else
       process_issue(@scraper.get_current_issue)
    end
  end

  def process_issue(issue)
    file =  @writer.write(issue)
    if @config['deliver_to']
      @postman.send(issue, file)
    end
  end

end

KindleTheEconomist.new.main