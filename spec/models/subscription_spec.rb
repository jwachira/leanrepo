require 'spec_helper'

describe Subscription do
  it { should have_one(:team).dependent(:destroy) }
  it { should belong_to(:plan) }
  it { should belong_to(:user) }

  it { should delegate(:stripe_customer_id).to(:user) }
  it { should delegate(:includes_mentor?).to(:plan) }
  it { should delegate(:includes_workshops?).to(:plan) }

  it { should validate_presence_of(:plan_id) }
  it { should validate_presence_of(:plan_type) }
  it { should validate_presence_of(:user_id) }

  it 'defaults paid to true' do
    Subscription.new.should be_paid
  end

  describe 'self.paid' do
    it 'only includes paid subscriptions' do
      paid = create(:subscription, paid: true)
      free = create(:subscription, paid: false)

      Subscription.paid.should_not include(free)
      Subscription.paid.should include(paid)
    end
  end

  describe '.deliver_welcome_emails' do
    it 'sends emails for each new mentored subscriber in the last 24 hours' do
      plan = create(:individual_plan, includes_mentor: true)
      old_subscription =
        create(:subscription, plan: plan, created_at: 25.hours.ago)
      new_subscription =
        create(:subscription, plan: plan, created_at: 10.hours.ago)
      mailer = stub(deliver: true)
      SubscriptionMailer.stubs(welcome_to_prime_from_mentor: mailer)

      Subscription.deliver_welcome_emails

      expect(SubscriptionMailer).
        to have_received(:welcome_to_prime_from_mentor).
        with(new_subscription.user)
      expect(SubscriptionMailer).
        to have_received(:welcome_to_prime_from_mentor).
        with(old_subscription.user).never
      expect(mailer).to have_received(:deliver).once
    end
  end

  describe '.next_payment_in_2_days' do
    it 'only includes subscription that will be billed in 2 days' do
      billed_today = create(:subscription, next_payment_on: Date.current)
      billed_tomorrow = create(:subscription, next_payment_on: Date.current + 1.day)
      billed_2_days_from_now = create(:subscription, next_payment_on: Date.current + 2.days)
      billed_3_days_from_now = create(:subscription, next_payment_on: Date.current + 3.days)

      expect(Subscription.next_payment_in_2_days).to eq [billed_2_days_from_now]
    end
  end

  describe '#active?' do
    it "returns true if deactivated_on is nil" do
      subscription = Subscription.new(deactivated_on: nil)
      subscription.should be_active
    end

    it "returns false if deactivated_on is not nil" do
      subscription = Subscription.new(deactivated_on: Time.zone.today)
      subscription.should_not be_active
    end
  end

  describe '#deactivate' do
    it "updates the subscription record by setting deactivated_on to today" do
      subscription = create(:active_subscription)

      subscription.deactivate
      subscription.reload

      expect(subscription.deactivated_on).to eq Time.zone.today
    end

    it 'unfulfills itself' do
      fulfillment = stub('fulfilment', :remove)
      subscription = create(:active_subscription)
      purchase = create(
        :purchase,
        user: subscription.user,
        purchaseable: subscription.plan
      )
      SubscriptionFulfillment.
        stubs(:new).
        with(purchase, subscription.user).
        returns(fulfillment)

      subscription.deactivate

      fulfillment.should have_received(:remove)
    end
  end

  describe '#change_plan' do
    it 'updates the plan in Stripe' do
      different_plan = create(:plan, sku: 'different')
      subscription = create(:active_subscription)
      stripe_customer = stub(update_subscription: nil)
      Stripe::Customer.stubs(:retrieve).returns(stripe_customer)

      subscription.change_plan(different_plan)

      expect(stripe_customer).
        to have_received(:update_subscription).
        with(plan: different_plan.sku)
    end

    it 'changes the subscription plan to the given plan' do
      different_plan = create(:plan, sku: 'different')
      subscription = create(:active_subscription)

      subscription.change_plan(different_plan)

      expect(subscription.plan).to eq different_plan
    end
  end

  describe '#has_access_to?' do
    context 'when the subscription is inactive' do
      it 'returns false' do
        subscription = build_stubbed(:subscription, deactivated_on: Date.today)

        expect(subscription.has_access_to?('workshops')).to be_false
      end
    end

    context 'when subscription is active but does not include feature' do
      it "returns false" do
        plan = create(:plan, includes_workshops: false)
        subscription = build_stubbed(:subscription, plan: plan)

        expect(subscription.has_access_to?('workshops')).to be_false
      end
    end

    context 'when subscription is active and includes feature' do
      it "returns true" do
        plan = create(:plan, includes_workshops: true)
        subscription = build_stubbed(:subscription, plan: plan)

        expect(subscription.has_access_to?('workshops')).to be_true
      end
    end
  end

  describe '#plan_name' do
    it 'delegates to plan' do
      plan = build_stubbed(:plan, name: 'Individual')
      subscription = build_stubbed(:subscription, plan: plan)

      expect(subscription.plan_name).to eq 'Individual'
    end
  end

  describe '.canceled_in_last_30_days' do
    it 'returns nothing when none have been canceled within 30 days' do
      create(:subscription, deactivated_on: 60.days.ago)

      expect(Subscription.canceled_in_last_30_days).to be_empty
    end

    it 'returns the subscriptions canceled within 30 days' do
      subscription = create(:subscription, deactivated_on: 7.days.ago)

      expect(Subscription.canceled_in_last_30_days).to eq [subscription]
    end
  end

  describe '.active_as_of' do
    it 'returns nothing when no subscriptions canceled' do
      expect(Subscription.active_as_of(Time.zone.now)).to be_empty
    end

    it 'returns nothing when subscription canceled before the given date' do
      create(:subscription, deactivated_on: 9.days.ago)

      expect(Subscription.active_as_of(8.days.ago)).to be_empty
    end

    it 'returns the subscriptions canceled after the given date' do
      subscription = create(:subscription, deactivated_on: 7.days.ago)

      expect(Subscription.active_as_of(8.days.ago)).to eq [subscription]
    end

    it 'returns the subscriptions not canceled' do
      subscription = create(:subscription)

      expect(Subscription.active_as_of(8.days.ago)).to eq [subscription]
    end
  end

  describe '.created_before' do
    it 'returns nothing when the are no subscriptions' do
      expect(Subscription.created_before(Time.zone.now)).to be_empty
    end

    it 'returns nothing when nothing has been created before the given date' do
      create(:subscription, created_at: 1.day.ago)

      expect(Subscription.created_before(2.days.ago)).to be_empty
    end

    it 'returns the subscriptions created before the given date' do
      subscription = create(:subscription, created_at: 2.days.ago)

      expect(Subscription.created_before(1.day.ago)).to eq [subscription]
    end
  end

  describe '#purchase' do
    it 'returns the purchase used to acquire this subscription' do
      stub_fulfillment

      user = create(:user)
      plan = create(:plan)
      other_plan = create(:plan)
      other_user = create(:user)
      subscription = create(:subscription, user: user, plan: plan)
      other_user_purchase =
        create(:plan_purchase, purchaseable: plan, user: other_user)
      other_plan_purchase =
        create(:plan_purchase, purchaseable: other_plan, user: user)
      subscription_purchase =
        create(:plan_purchase, purchaseable: plan, user: user)

      expect(subscription.purchase).to eq(subscription_purchase)
    end

    def stub_fulfillment
      fulfillment = stub('fulfillment', :fulfill)
      SubscriptionFulfillment.stubs(:new).returns(fulfillment)
    end
  end

  describe '#team?' do
    it 'returns true with a team' do
      subscription = create(:team).subscription

      expect(subscription.team?).to be_true
    end

    it 'returns false without a team' do
      subscription = build_stubbed(:subscription)

      expect(subscription.team?).to be_false
    end
  end

  describe '#last_charge' do
    it 'returns the last charge for the customer' do
      charge = stub('Stripe::Charge')
      Stripe::Charge.stubs(:all).returns([charge])
      subscription = build_stubbed(:subscription)

      expect(subscription.last_charge).to eq charge
      expect(Stripe::Charge).to have_received(:all)
        .with(count: 1, customer: subscription.stripe_customer_id)
    end
  end
end
