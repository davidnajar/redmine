# redMine - project management software
# Copyright (C) 2006-2007  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require 'redmine/scm/adapters/abstract_adapter'
require 'grit'



module Redmine
  module Scm
    module Adapters    
      class GitAdapter < AbstractAdapter
        attr_accessor :repo

        # Git executable name
        GIT_BIN = "git"

        def initialize(*args)
          args[1] = args[0]
          super(*args)
          @repo = Grit::Repo.new(url, :is_bare => true)
        end

        def info
          revs = revisions('',nil,nil,{:limit => 1})
          if revs && revs.any?
            Info.new(:root_url => url, :lastrev => revs.first)
          else
            nil
          end
        rescue Errno::ENOENT => e
          return nil
        end

        def branches
          @repo.branches
        end
        
        def entries(path=nil, identifier=nil)
          path = nil if path.empty?
          identifier = repo.default_branch if identifier.nil? 

          entries = Entries.new
          
          tree = repo.log(identifier, path).first.tree 
          tree = tree / path if path

          tree.contents.each do |file|
            files = []
            file_path = path ? "#{path}/#{file.name}" : file.name
            commit = repo.log('all', file_path, :n => 1).first

            rev = Revision.new({
              :identifier => commit.id,
              :scmid => commit.id,
              :author => "#{commit.author.name} <#{commit.author.email}>",
              :time => commit.committed_date,
              :message => commit.message
            })

            entries << Entry.new({
              :name => file.name,
              :path => file_path,
              :kind => file.class == Grit::Blob ? 'file' : 'dir',
              :size => file.respond_to?('size') ? file.size : nil,
              :lastrev => rev
            })
          end

          entries.sort_by_name
        end

        def revisions(path, identifier_from, identifier_to, options={})
          revisions = Revisions.new
          path = 'all' if path.empty?
          
          commits = repo.log(path,nil,:n => options[:limit]) if options[:limit]
          commits ||= repo.log(path)

          revisions = commits.collect{|c| c.to_revision}
        end

        def initialize_database(repository)
          repo.log('all').each do |c| 
            begin
              c.to_revision.save(repository)
            rescue
              logger.error 'Encountered Nasty Revision'
            end
          end
        end

        def diff(path, identifier_from, identifier_to=nil)
          path ||= ''
          if !identifier_to
            identifier_to = nil
          end
          
          cmd = "#{GIT_BIN} --git-dir #{target('')} show #{shell_quote identifier_from}" if identifier_to.nil?
          cmd = "#{GIT_BIN} --git-dir #{target('')} diff #{shell_quote identifier_to} #{shell_quote identifier_from}" if !identifier_to.nil?
          cmd << " -- #{shell_quote path}" unless path.empty?
          diff = []
          shellout(cmd) do |io|
            io.each_line do |line|
              diff << line
            end
          end
          return nil if $? && $?.exitstatus != 0
          diff
        end
        
        def annotate(path, identifier=nil)
          identifier = 'HEAD' if identifier.blank?
          cmd = "#{GIT_BIN} --git-dir #{target('')} blame -l #{shell_quote identifier} -- #{shell_quote path}"
          blame = Annotate.new
          content = nil
          shellout(cmd) { |io| io.binmode; content = io.read }
          return nil if $? && $?.exitstatus != 0
          # git annotates binary files
          return nil if content.is_binary_data?
          content.split("\n").each do |line|
            next unless line =~ /([0-9a-f]{39,40})\s\((\w*)[^\)]*\)(.*)/
            blame.add_line($3.rstrip, Revision.new(:identifier => $1, :author => $2.strip))
          end
          blame
        end
        
        def cat(path, identifier=nil)
          if identifier.nil?
            identifier = 'HEAD'
          end
          cmd = "#{GIT_BIN} --git-dir #{target('')} show #{shell_quote(identifier + ':' + path)}"
          cat = nil
          shellout(cmd) do |io|
            io.binmode
            cat = io.read
          end
          return nil if $? && $?.exitstatus != 0
          cat
        end
      end
    end
  end
end

module Grit
  class Repo
    def log(commit = 'master', path = nil, options = {})
      default_options = {:pretty => "raw", "no-merges" => true}

      if commit == 'all'
        commit = 'master'
        default_options.merge!(:all => true)
      end

      actual_options  = default_options.merge(options)
      arg = path ? [commit, '--', path] : [commit]
      commits = self.git.log(actual_options, *arg)
      Commit.list_from_string(self, commits)
    end

    def default_branch
      if branches.map{|h| h.name}.include?('master') 
        'master'
      else
        branches.first.name
      end
    end
  end

  class Diff
    def action
      return 'A' if new_file
      return 'D' if deleted_file
      return 'M'
    end

    def path
      return a_path if a_path
      return b_path if b_path
    end
  end

  class Commit
    def to_revision
      Redmine::Scm::Adapters::Revision.new({
        :identifier => id,
        :scmid => id,
        :author => "#{author.name} <#{author.email}>",
        :time => committed_date,
        :message => message,
        :paths => show.collect{|d| {:action => d.action, :path => d.path}}
      })
    end
  end
end
