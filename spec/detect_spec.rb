require 'uri'
require 'net/http'
require 'socket'
require 'net/ssh'

module RemoteRepo
  class GitHTTP
    def self.scheme(url)
      case url.scheme
      when 'http'; 1.0
      when 'https'; 1.0
      when nil; 0.5
      else; 0.0
      end
    end

    def self.path(url)
      case url.path
      when /\.git$/; 1.0
      else 0.5
      end
    end

    def self.guess(path)
      url = URI.parse(path)
      scheme(url) * 0.5 + 
        self.path(url) * 0.5
    rescue URI::InvalidURIError
      return 0.0
    end

    # Standard HTTP server (Apache, etc)
    def self.test(path)
      begin
        url = URI.parse(path + '/info/refs')
      rescue URI::InvalidURIError
        return nil
      end
      req = Net::HTTP::Get.new(url.path)
      res = Net::HTTP.start(url.host, url.port) {|http|
        http.request(req)
      }
      res.body.match(/refs\/heads/)
    end
  end

  class GitGit
    def self.scheme(url)
      case url.scheme
      when 'git'; 1.0
      when nil; 0.5 * path(url)
      else; 0.0
      end
    end

    def self.path(url)
      case url.path
      when /\.git$/; 1.0
      else; 0.5
      end
    end

    def self.guess(path)
      url = URI.parse(path)
      scheme(url)
    rescue URI::InvalidURIError
      return 0.0
    end

    # git daemon --verbose --base-path=.
    # touch ac.g/git-daemon-export-ok
    def self.test(path)
      begin
        url = URI.parse(path)
      rescue URI::InvalidURIError
        return nil
      end
      con = TCPSocket.open(url.host, url.port || 9418)
      # 0039git-upload-pack /schacon/gitbook.git\0host=github.com\0
      # con.write("0029git-upload-pack /ac.g\0host=localhost\0")
      request = "git-upload-pack #{url.path}\0host=#{url.host}\0"
      request = "%0.4x" % (request.size + 4) + request
      con.write(request)
      select([con], nil, nil, 5)
      con.read_nonblock(1024).match(/ HEAD\0/)
    rescue Errno::EAGAIN
      nil
    rescue EOFError
      nil
    ensure
      con.close if con
    end
  end

  class GitSSH
    def self.parse_uri(path)
      return nil unless path.match(/([\w.]+)@([\w.]+):(\D.+)/)
      user, host, dir = $1, $2, $3
      URI::Generic.new('ssh', user, host, 443, nil, dir, nil, nil, nil) 
    rescue URI::InvalidURIError
      return nil
    end

    def self.scheme(url)
      case url.scheme
      when 'ssh'; 1.0
      when nil; 0.5
      else; 0.0
      end
    end

    def self.path(url)
      case url.path
      when /\.git$/; 1.0
      else 0.5
      end
    end

    def self.guess(path)
      return 0.0 unless url = parse_uri(path)
      scheme(url) * 0.5 + 
        self.path(url) * 0.5
    end

    def self.test(path)
      return nil unless url = parse_uri(path)
      Net::SSH.start(url.host, url.user,
          :verbose => Logger::WARN,
          :auth_methods => ['publickey'],
          ) do |ssh|
        ssh.exec("/opt/local/bin/git receive-pack #{url.path}") do |ch, stream, data|
          if (stream == :stdout)
            ch.close
            return data.match(/ refs\/heads/)
          end
        end
      end
      return nil
    end
  end

  class MercurialHTTP
    def self.scheme(url)
      case url.scheme
      when 'http'; 1.0
      when 'https'; 1.0
      when nil; 0.5
      else; 0.0
      end
    end

    def self.path(url)
      case url.path
      when /\.hg$/; 1.0
      else 0.5
      end
    end

    def self.host(url)
      case url.host
      when /bitbucket/; 1.0
      else; 0.0
      end
    end

    def self.guess(path)
      url = URI.parse(path)
      scheme(url) * 0.6 + 
        self.path(url) * 0.1 +
        host(url) * 0.3
    rescue URI::InvalidURIError
      return 0.0
    end

    # hgweb or hg serve
    def self.test(path)
      begin
        url = URI.parse(path)
      rescue URI::InvalidURIError
        return nil
      end
      req = Net::HTTP::Get.new(url.path + '?cmd=capabilities')
      res = Net::HTTP.start(url.host, url.port) {|http|
        http.request(req)
      }
      res.body.match(/lookup/)
    end
  end

  class MercurialSSH
    def self.scheme(url)
      case url.scheme
      when 'ssh'; 1.0
      when nil; 0.5
      else; 0.0
      end
    end

    def self.path(url)
      case url.path
      when /\.hg$/; 1.0
      else 0.5
      end
    end

    def self.host(url)
      case url.host
      when /bitbucket/; 1.0
      else; 0.0
      end
    end

    def self.guess(path)
      url = URI.parse(path)
      scheme(url) * 0.6 + 
        self.path(url) * 0.1 +
        host(url) * 0.3
    rescue URI::InvalidURIError
      return 0.0
    end

    def self.test(path)
      begin
        url = URI.parse(path)
      rescue URI::InvalidURIError
        return nil
      end
      Net::SSH.start(url.host, url.user,
          :verbose => Logger::WARN,
          :auth_methods => ['publickey'],
          ) do |ssh|
        ssh.open_channel do |channel|
          channel.exec("/opt/local/bin/hg -R #{url.path} serve --stdio") do |chan, success|
            abort "could not execute command" unless success
            channel.send_data "hello\n"
            chan.on_data do |ch, data|
              ch.close
              return data.match(/lookup/)
            end
          end
        end
      end
      return nil
    rescue Net::SSH::AuthenticationFailed
      return nil
    end
  end

  class Unidentified
  end

  REPOS = [
    GitHTTP,
    GitGit,
    GitSSH,
    MercurialHTTP,
    MercurialSSH,
  ]

  def self.sort(url)
    REPOS.sort_by {|repo| repo.guess(url)}.reverse!
  end

  def self.guess(url)
    sort(url).first
  end

  def self.interrogate(url)
    sort(url).each do |repo|
      return repo if repo.test(url)
    end
    return Unidentified
  end
end

describe RemoteRepo do
  context RemoteRepo::GitGit do
    let(:path) {'git://github.com/michaeledgar/amp_redux.git'}
    let(:url) {URI.parse(path)}

    it 'gets the right scheme' do
      RemoteRepo::GitGit.scheme(url).should == 1.0
    end

    it 'likes the path' do
      RemoteRepo::GitGit.path(url).should == 1.0
    end

    it 'maximally rated' do
      RemoteRepo::GitGit.guess(path).should == 1.0
    end
  end

  context RemoteRepo::GitSSH do
    let(:path) {'git@github.com:michaeledgar/bitbucket.git'}

    it 'parses uris' do
      RemoteRepo::GitSSH.parse_uri(path).should be_kind_of(URI)
    end
  end

  context RemoteRepo::MercurialHTTP do
    let(:path) {'https://JustinLove@bitbucket.org/JustinLove/amp'}
    let(:url) {URI.parse(path)}

    it 'likes the scheme' do
      RemoteRepo::MercurialHTTP.scheme(url).should == 1.0
    end

    it 'is highly rated' do
      RemoteRepo::MercurialHTTP.guess(path).should > 0.75
    end
  end

  context "easily guessed names" do
    module RemoteRepo
      {
        'https://github.com/michaeledgar/amp_complete.git' => GitHTTP,
        'git@github.com:michaeledgar/amp_redux.git' => GitSSH,
        'git://github.com/michaeledgar/amp_redux.git' => GitGit,
        'git@github.com:michaeledgar/bitbucket.git' => GitSSH,
        'http://foo.bar/bitbucket.git' => GitHTTP,
        'https://JustinLove@bitbucket.org/JustinLove/amp' => MercurialHTTP,
        'ssh://hg@bitbucket.org/JustinLove/amp' => MercurialSSH,
        'ssh://hg@bitbucket.org/JustinLove/git' => MercurialSSH,
      }
    end.each do |url,repo|
      it "guesses #{url} as #{repo}" do
        RemoteRepo.guess(url).should == repo
      end
    end
  end

  context "Server interrogation" do
    module RemoteRepo
      {
        'http://localhost/~jlove/ac.g' => GitHTTP,
        'git://localhost/ac.g' => GitGit,
        'jlove@localhost:Sites/ac.g' => GitSSH,
        'http://localhost:8000/' => MercurialHTTP,
        'ssh://jlove@localhost/Users/jlove/Sites/amp' => MercurialSSH,
      }
    end.each do |url,repo|
      context url do
        RemoteRepo::REPOS.each do |candidate|
          context candidate do
            if (candidate == repo)
              it "accepted" do
                candidate.test(url).should be
              end
            else
              it "rejected" do
                candidate.test(url).should_not be
              end
            end
          end
        end

        it "interrogates as #{repo}" do
          RemoteRepo.interrogate(url).should == repo
        end
      end
    end
  end
end
