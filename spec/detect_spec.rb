require 'uri'
require 'net/http'

module RemoteRepo
  class GitHTTP
    # Standard HTTP server (Apache, etc)
    def self.test(path)
      url = URI.parse(path + '/info/refs')
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
  end

  class GitSSH
  end

  class Mercurial
  end

  class Unidentified
  end

  def self.guess(url)
    case url
    when /http.+\.git$/; GitHTTP
    when /git@.+\.git$/; GitSSH
    when /git:.+\.git$/; GitGit
    when /bitbucket/; Mercurial
    else nil
    end
  end

  def self.interrogate(url)
    GitHTTP.test(url) && GitHTTP
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
        'https://JustinLove@bitbucket.org/JustinLove/amp' => Mercurial,
        'ssh://hg@bitbucket.org/JustinLove/amp' => Mercurial,
        'ssh://hg@bitbucket.org/JustinLove/git' => Mercurial,
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
        # InvalidURIError 'git@github.com:michaeledgar/amp_redux.git' => GitSSH,
        # GitHTTP 'git://github.com/michaeledgar/amp_redux.git' => GitGit,
        # Connection reset by peer 'https://JustinLove@bitbucket.org/JustinLove/amp' => Mercurial,
        # nil 'ssh://hg@bitbucket.org/JustinLove/amp' => Mercurial,
      }
    end.each do |url,repo|
      it "interrogates #{url} as #{repo}" do
        RemoteRepo.interrogate(url).should == repo
      end
    end
  end
end
