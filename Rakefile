require 'rspec/core/rake_task'

task :default => :spec

RSpec::Core::RakeTask.new do |t|
end

task :setup do
  mkdir 'webroot' unless File.exist?('webroot')
  system 'git clone --bare . webroot/detect.g'
  system 'cd webroot/detect.g; git update-server-info'
  touch 'webroot/detect.g/git-daemon-export-ok'
  system 'hg clone http://bitbucket.org/JustinLove/amp webroot/amp'
end

task :'server:http' do
  require 'webrick'

  begin
    server = WEBrick::HTTPServer.new(:Port => 8080, :DocumentRoot => 'webroot')
    ['INT', 'TERM'].each { |signal|
       trap(signal){ server.shutdown} 
    }
    server.start
  ensure
    server.shutdown if server
  end
end

task :'server:git' do
  system 'git daemon --verbose --base-path=webroot'
end

task :'server:hg' do
  system 'hg -R webroot/amp serve'
end
