#!/usr/bin/env ruby
require 'fileutils'
BZR_EXPORT_CMD = "bzr fast-export"

command = ARGV.shift
commands = [:add, :push, :fetch, :pull]

if !command || !commands.include?(command.to_sym)
  puts "Usage: git bzr [COMMAND] [OPTIONS]"
  puts "Commands: add, push, fetch, pull"
  exit
end

class BzrCommands

  def add(*args)
    name = args.shift
    location = args.shift
    unless name && location && args.empty?
      puts "Usage: git bzr add name location"
      exit
    end
    if `git remote show`.split("\n").include?(name)
      puts "There is already a remote with that name"
      exit
    end

    if `git config git-bzr.#{name}.url` != ""
      puts "There is alread a bazaar branch with that name"
      exit
    end

    if !File.exists?(File.join(location, ".bzr"))
      puts "Remote is not a bazaar repository"
      exit
    end

    `git config git-bzr.#{name}.location #{location}`
    puts "Bazaar branch #{name} added. You can fetch it with `git bzr fetch #{name}`"

  end

  def get_location(remote)
    l = `git config git-bzr.#{remote}.location`.strip
    if l == ""
      puts "Cannot find bazaar remote with name `#{remote}`."
      exit
    end
    l
  end

  def fetch(*args)
    remote = args.shift
    unless remote && args.empty?
      puts "Usage: git bzr fetch branchname"
      exit
    end
    location = get_location(remote)

    git_map = File.expand_path(File.join(git_dir, "bzr-git", "#{remote}-git-map"))
    bzr_map = File.expand_path(File.join(git_dir, "bzr-git", "#{remote}-bzr-map"))

    if !File.exists?(git_map) && !File.exists?(bzr_map)
      print "There doesn't seem to be an existing refmap. "
      puts "Doing an initial import"
      FileUtils.makedirs(File.dirname(git_map))
      `(#{BZR_EXPORT_CMD} --export-marks=#{bzr_map} --git-branch=bzr/#{remote} #{location}) | (git fast-import --export-marks=#{git_map})`
    elsif File.exists?(git_map) && File.exists?(bzr_map)
      puts "Updating remote #{remote}"
      old_rev = `git rev-parse bzr/#{remote}`
      `(#{BZR_EXPORT_CMD} --import-marks=#{bzr_map} --export-marks=#{bzr_map} --git-branch=bzr/#{remote} #{location}) | (git fast-import --quiet --export-marks=#{git_map} --import-marks=#{git_map})`
      new_rev = `git rev-parse bzr/#{remote}`
      puts "Changes since last update:"
      puts `git shortlog #{old_rev.strip}..#{new_rev.strip}`
    else
      puts "One of the mapfiles is missing! Something went wrong!"
    end
  end

  def push(*args)
    remote = args.shift
    unless remote && args.empty?
      puts "Usage: git bzr push branchname"
      exit
    end
    location = get_location(remote)

    if `git rev-list --left-right HEAD...bzr/#{remote} | sed -n '/^>/ p'`.strip != ""
      puts "HEAD is not a strict child of #{remote}, cannot push. Merge first"
      exit
    end

    if `git rev-list --left-right HEAD...bzr/#{remote} | sed -n '/^</ p'`.strip == ""
      puts "Nothing to push. Commit something first"
      exit
    end

    git_map = File.expand_path(File.join(git_dir, "bzr-git", "#{remote}-git-map"))
    bzr_map = File.expand_path(File.join(git_dir, "bzr-git", "#{remote}-bzr-map"))

    if !File.exists?(git_map) || !File.exists?(bzr_map)
      puts "We do not have refmapping yet. Then how can I push?"
      exit
    end

    `(git fast-export --import-marks=#{git_map} --export-marks=#{git_map} HEAD) | (cd #{location} && bzr fast-import --import-marks=#{bzr_map} --export-marks=#{bzr_map} -)`
  end

  def git_dir
    `git rev-parse --git-dir`.strip
  end

  def run(cmd, *args)
    `git rev-parse 2> /dev/null`
    if $? != 0
      puts "Must be inside a git repository to work"
      exit
    end
    up = `git rev-parse --show-cdup`.strip
    up = "." if up == ""
    Dir.chdir(up) do
      __send__(cmd.to_s, *args)
    end
  end
end


BzrCommands.new.run(command, *ARGV)
