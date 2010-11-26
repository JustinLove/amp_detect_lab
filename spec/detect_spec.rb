require 'uri'
require 'net/http'
require 'socket'
require 'net/ssh'

module RemoteRepo
  class GitHTTP
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
    def self.test(path)
      return nil unless path.match(/(\w+)@(\w+):(\D.+)/)
      user, host, dir = $1, $2, $3
      Net::SSH.start(host, user,
          :verbose => Logger::WARN,
          :auth_methods => ['publickey'],
          ) do |ssh|
        ssh.exec("/opt/local/bin/git receive-pack #{dir}") do |ch, stream, data|
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
    end
  end

  class Unidentified
  end

  def self.guess(url)
    case url
    when /http.+\.git$/; GitHTTP
    when /git@.+\.git$/; GitSSH
    when /git:.+\.git$/; GitGit
    when /http.+bitbucket/; MercurialHTTP
    when /hg@bitbucket.org/; MercurialSSH
    else nil
    end
  end

  def self.interrogate(url)
    [GitHTTP, GitGit, GitSSH, MercurialHTTP, MercurialSSH].each do |repo|
      return repo if repo.test(url)
    end
    return nil
  end

  def self.pick(url)
    (guess(url) || interrogate(url) || Unidentified).new
  end
end

describe RemoteRepo do
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
      it "interrogates #{url} as #{repo}" do
        RemoteRepo.interrogate(url).should == repo
      end
    end
  end
end
