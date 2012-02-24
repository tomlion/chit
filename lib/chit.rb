$:.unshift File.dirname(__FILE__)
%w(rubygems git tempfile fileutils yaml wrap).each {|f| require f}

module Chit
  extend self

  defaults = {
    'root'  => File.join("#{ENV['HOME']}",".chit")
  }

  CHITRC = File.join("#{ENV['HOME']}",".chitrc")

  FileUtils.cp(File.join(File.dirname(__FILE__), "..","resources","chitrc"), CHITRC) unless File.exist?(CHITRC)

  CONFIG = defaults.merge(YAML.load_file(CHITRC))

  def run(args)
    unless File.exist?(main_path) && File.exist?(private_path)
      return unless init_chit
    end
    args = args.dup

    return unless parse_args(args)

    if %w[sheets all].include? @sheet
      return with_stdout_redirected_to(pipe_to_pager) { list_all() }
    end

    #unless File.exist?(sheet_file)
      #update
    #end

    unless File.exist?(sheet_file)
      puts "Error!:\n  #{@sheet} not found"
      puts "Possible sheets:"
      search_title
    else
      format = 'html' if args.delete('--html')
      with_stdout_redirected_to(pipe_to_pager) { show(sheet_file, format) }
    end
  end

  def parse_args(args)
    init_chit and return if args.delete('--init')
    update and return if args.delete('--update')

    @sheet = args.shift || 'chit'
    @sheet = 'chit' if @sheet == '--help'

    @working_dir, @fullpath = detect_fullpath(@sheet)
    @git = Git.open(@working_dir)

    add(sheet_file) and return if (args.delete('--add')||args.delete('-a'))
    edit(sheet_file) and return if (args.delete('--edit')||args.delete('-e'))
    search_title and return if (args.delete('--find')||args.delete('-f'))
    search_content and return if (args.delete('--search')||args.delete('-s'))

    if (args.delete('--mv') || args.delete('-m'))
      target = args.shift
      mv_to(target) and return if target
      puts "Target not specified!"
      return
    end
    true
  end

  def list_all
    puts all_sheets.sort.join("\n")
  end

  def mv_to(target)
    if target =~ /^@(.*)/
      target = $1
    end
    target_path = File.join(@working_dir, "#{target}.yml")
    prepare_dir(target_path)
    @git.lib.mv(sheet_file, target_path)
    sheet = YAML.load(IO.read(target_path)).to_a.first
    body = sheet[-1]
    title = parse_title(target)
    open(target_path,'w') {|f| f << {title => body}.to_yaml}
    @git.add
    @git.commit_all(" #{@sheet} moved to #{target}")
  end

  def search_content
    @git.grep(@sheet).each {|file, lines|
      title = title_of_file(file.split(':')[1])
      lines.each {|l|
        puts "#{title}:#{l[0]}:  #{l[1]}"
      }
    }
  end

  def search_title
    reg = Regexp.compile("#{@sheet}")
    files = all_sheets.select {|sheet| sheet =~ reg }
    puts "  " + files.sort.join("\n  ")
    true
  end


  def detect_fullpath(sheet)
    is_private = (sheet =~ /^@(.*)/)
    sheet_name = is_private ? $1 : sheet

    path1 = File.join( main_path, "#{sheet_name}.yml")
    path2 = File.join( private_path, "#{sheet_name}.yml")

    return [private_path, path2] if is_private and File.exist?(path2)
    return [main_path, path1] if File.exist?(path1)
    return [private_path, path2] if File.exist?(path2)
    return [(is_private ? private_path : main_path), nil]
  end

  def sheet_file
    @fullpath || ""
  end

  def init_chit
    FileUtils.mkdir_p(CONFIG['root'])
    if CONFIG['main']['clone-from']
      if File.exist?(main_path)
        puts "Main chit has already been initialized."
      else
        puts "Initialize main chit from #{CONFIG['main']['clone-from']} to #{CONFIG['root']}/main"
        Git.clone(CONFIG['main']['clone-from'], 'main', :path => CONFIG['root'])
        puts "Main chit initialized."
      end
    else
      puts "ERROR: configuration for main chit repository is missing!"
      return
    end

    unless File.exist?(private_path)
      if CONFIG['private'] && CONFIG['private']['clone-from']
        puts "Initialize private chit from #{CONFIG['private']['clone-from']} to #{CONFIG['root']}/private"
        Git.clone(CONFIG['private']['clone-from'], 'private', :path => CONFIG['root'])
        puts "Private chit initialized."
      else
        puts "Initialize private chit from scratch to #{CONFIG['root']}/private"
        git = Git.init(private_path)
        FileUtils.touch(File.join(CONFIG['root'],'private','.gitignore'))
        git.add
        git.commit_all("init private repository")
        puts "Private chit initialized."
      end
    else
      puts "Private chit has already been initialized."
    end
    puts "Chit init done."
    true
  end

  def update
    if CONFIG['main']['clone-from']
      g = Git.open(main_path)
      g.pull
    end
  rescue
    puts "ERROR: can not update main chit."
    puts $!
  end

  def main_path
    File.join(CONFIG['root'], 'main')
  end

  def private_path
    File.join(CONFIG['root'], 'private')
  end

  def pager_program
    ENV['PAGER'] || "more"
  end

  def pipe_to_pager
    IO.popen(pager_program, "w")
  end

  def with_stdout_redirected_to(io)
    orig_stdout = $stdout
    $stdout = io
    yield
    $stdout.close
  ensure
    $stdout = orig_stdout
  end

  def show(file,format=nil)
    sheet = YAML.load(IO.read(file)).to_a.first
    sheet[-1] = sheet.last.join("\n") if sheet[-1].is_a?(Array)
    case format
    when 'html'
      puts "<h1>#{sheet.first}</h1>"
      puts "<pre>#{sheet.last.gsub("\r",'').gsub("\n", "\n  ").wrap}</pre>"
    else
      puts sheet.first + ':'
      puts '  ' + sheet.last.gsub("\r",'').gsub("\n", "\n  ").wrap
    end
  end

  def rm(file)
    @git.remove(file)
    @git.commit_all("#{@sheet} removed")
  rescue Git::GitExecuteError
    FileUtils.rm_rf(file)
  end

  def add(file)
    unless File.exist?(file)
      prepare_dir(file)
      title = parse_title(@sheet)
      yml = {"#{title}" => ''}.to_yaml
      open(file, 'w') {|f| f << yml}
    end
    edit(file)
  end

  def edit(file)
    sheet = YAML.load(IO.read(file)).to_a.first
    sheet[-1] = sheet.last.gsub("\r", '')
    body, title = write_to_tempfile(*sheet), sheet.first
    if body.strip.empty?
      rm(file)
    else
      open(file,'w') {|f| f << {title => body}.to_yaml}
      @git.add
      st = @git.status
      unless st.added.empty? && st.changed.empty? && st.deleted.empty? && st.untracked.empty?
        @git.commit_all(" #{@sheet} updated")
      end
    end
    true
  end

  private
  def parse_title(sheet_name)
    sheet_name.split(File::Separator).join('::')
  end

  def prepare_dir(file)
    breaker = file.rindex(File::Separator)+1
    path = file[0,breaker]
    FileUtils.mkdir_p(path)
  end

  def editor
    ENV['VISUAL'] || ENV['EDITOR'] || "vim"
  end

  def write_to_tempfile(title, body = nil)
    title = title.gsub(/\/|::/, '-')
    # god dammit i hate tempfile, this is so messy but i think it's
    # the only way.
    tempfile = Tempfile.new(title + '.cheat')
    tempfile.write(body) if body
    tempfile.close
    system "#{editor} #{tempfile.path}"
    tempfile.open
    body = tempfile.read
    tempfile.close
    body
  end

  def all_sheets
    all_public_sheets + all_private_sheets
  end

  def all_public_sheets
    @git.ls_files.to_a.map {|f| title_of_file(f[0])}
  end

  def all_private_sheets
    @private_git = Git.open(private_path)
    @private_git.ls_files.to_a.map {|f| "@"+title_of_file(f[0])}
  end

  def title_of_file(f)
    f[0..((f.rindex('.')||0) - 1)]
  end

end
