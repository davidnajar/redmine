# redMine - project management software
# Copyright (C) 2006-2007  Jean-Philippe Lang
# Copyright (C) 2007  Patrick Aljord patcito@ŋmail.com
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

require 'redmine/scm/adapters/git_adapter'

class Repository::Git < Repository
  attr_protected :root_url
  validates_presence_of :url

  def scm_adapter
    Redmine::Scm::Adapters::GitAdapter
  end
  
  def self.scm_name
    'Git'
  end

  def changesets_for_path(path, options={})
    Change.find(:all, :include => {:changeset => :user}, 
                :conditions => ["repository_id = ? AND path = ?", id, path],
                :order => "committed_on DESC, #{Changeset.table_name}.revision DESC",
                :limit => options[:limit]).collect(&:changeset)
  end

  def fetch_changesets
    # latest revision found in database
    db_revision = latest_changeset ? latest_changeset.revision : nil

    # latest revision in the repository
    scm_revision = scm.info.lastrev.scmid

    if db_revision.nil?
      scm.initialize_database(self)
    end

    unless changesets.find_by_scmid(scm_revision)
      scm.revisions('', db_revision, nil, :reverse => true).each do |revision|
        revision.save(self)
      end
    end
  end

  def branches
    scm.branches
  end
end
