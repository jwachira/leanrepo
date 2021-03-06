namespace :dev do
  desc 'Creates sample data for local development'
  task prime: ['db:setup'] do
    unless Rails.env.development?
      raise 'This task can only be run in the development environment'
    end

    require 'factory_girl_rails'

    create_products
    create_workshops
    create_mentors
    create_users
    create_team_plan
    create_topic
    create_individual_plans
  end

  def create_products
    header "Products"

    @prime = FactoryGirl.create(:plan)
    puts_product @prime
    @book = FactoryGirl.create(
      :book,
      :promoted,
      sku: 'VIM',
      name: 'Vim for Rails Developers'
    )
    puts_product @book

    puts_product FactoryGirl.create(:screencast, :promoted)
    puts_product FactoryGirl.create(:screencast, :promoted)

    puts_product FactoryGirl.create(:show, name: 'The Weekly Iteration')
  end

  def create_workshops
    header "Workshops"

    @workshop = FactoryGirl.create(:workshop,
      name: 'Intermediate Ruby on Rails',
      short_description: 'Dig deeper into Ruby on Rails.',
      description: 'This intermediate Ruby on Rails workshop is designed for developers who have built a few smaller Rails applications and would like to start making more complicated ones...'
    )
    puts_workshop @workshop
  end

  def create_users
    header "Users"

    user = FactoryGirl.create(:admin, email: 'admin@example.com')
    puts_user user, 'admin'

    user = FactoryGirl.create(:admin,
                              :with_subscription,
                              :with_github,
                              plan: @prime,
                              email: 'whetstone@example.com')
    puts_user user, 'ready to auth against whetstone'

    user = FactoryGirl.create(:user, email: 'none@example.com')
    puts_user user, 'no purchases'

    user = FactoryGirl.create(:user, email: 'product@example.com')
    FactoryGirl.create :purchase, :free, user: user, purchaseable: @book
    puts_user user, 'product purchase'

    user = FactoryGirl.create(:user, email: 'prime@example.com')
    FactoryGirl.create :purchase, :free, user: user, purchaseable: @prime
    puts_user user, 'prime purchase'

    user = FactoryGirl.create(:user, email: 'workshop@example.com')
    FactoryGirl.create :purchase, :free, user: user, purchaseable: @workshop
    puts_user user, 'workshop purchase'

    user = FactoryGirl.create(:user, email: 'both@example.com')
    FactoryGirl.create :purchase, :free, user: user, purchaseable: @book
    FactoryGirl.create :purchase, :free, user: user, purchaseable: @workshop
    puts_user user, 'product and workshop purchase'

    puts "\n"
  end

  def create_mentors
    header "Mentors"

    mentor = FactoryGirl.create(:user, email: 'mentor@example.com', admin: true)
    FactoryGirl.create(:mentor, user: mentor)
    puts_user mentor, 'mentor'

    puts "\n"
  end

  def create_team_plan
    FactoryGirl.create(:team_plan)
  end

  def create_topic
    FactoryGirl.create(:topic, name: 'Ruby on Rails')
  end

  def create_individual_plans
    [29, 49, 249].each do |n|
      FactoryGirl.create(:plan, sku: "prime_#{n}", individual_price: n)
    end
  end

  def header(msg)
    puts "\n\n*** #{msg.upcase} *** \n\n"
  end

  def puts_product(product)
    puts "#{product.name}"
  end

  def puts_workshop(workshop)
    puts "#{workshop.name}"
  end

  def puts_workshop(workshop)
    puts "#{workshop.name} (#{workshop.starts_on} - #{workshop.ends_on})"
  end

  def puts_user(user, description)
    puts "#{user.email} / #{user.password} (#{description})"
  end
end
