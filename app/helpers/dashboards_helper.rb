module DashboardsHelper
  def learn_live_link(&block)
    if current_user_has_access_to?(:office_hours)
      link_to OfficeHours.url, target: "_blank", &block
    else
      content_tag "a", &block
    end
  end

  def learn_repo_link(&block)
    if current_user_has_access_to?(:source_code)
      link_to ENV['LEARN_REPO_URL'], target: "_blank", &block
    else
      content_tag "a", &block
    end
  end

  def locked_features
    features.reject { |feature| current_user_has_access_to?(feature) }
  end

  def locked_features_text
    locked_features.to_sentence.capitalize
  end

  def subscribe_or_upgrade
    if current_user_has_active_subscription?
      t(".locked_features.upgrade_link")
    else
      t(".locked_features.subscribe_link")
    end
  end

  def features
    %i(books exercises screencasts shows workshops)
  end
end
