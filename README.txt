This is a prototype lab for detecting the type of a remote VCS repository given one of it's urls.  It is not meant to be any kind of stand alone application.

## Setup

Your computer should have git and hg installed, and have a SSH server running.

One-time:

  bundle install
  rake setup

Each session: In three terminal windows/tabs:

  rake server:http
  rake server:git
  rake server:hg

Running tests:

  rake
  or
  rake spec

