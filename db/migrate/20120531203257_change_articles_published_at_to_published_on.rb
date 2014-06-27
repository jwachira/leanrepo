class ChangeArticlesPublishedAtToPublishedOn < ActiveRecord::Migration
  def up
    rename_column :articles, :published_at, :published_on
  end

  def down
    rename_column :articles, :published_on, :published_at
  end
end
