require 'spec_helper'

describe Purchase do
  context 'validations' do
    subject { described_class.new(purchaseable: create(:product)) }
    it { should belong_to(:user) }
    it { should validate_presence_of(:email) }
    it { should validate_presence_of(:quantity) }
    it { should allow_value('chad-help@co.uk').for(:email) }
    it { should allow_value('chad-help@thoughtbot.com').for(:email) }
    it { should allow_value('chad.help@thoughtbot.com').for(:email) }
    it { should allow_value('chad@thoughtbot.com').for(:email) }
    it { should_not allow_value('chad').for(:email) }
    it { should_not allow_value('chad@blah').for(:email) }
    it { should_not validate_presence_of(:user_id) }

    it { should delegate(:subscription?).to(:purchaseable) }
    it { should delegate(:includes_mentor?).to(:purchaseable) }
  end

  context '#price' do
    it 'produces the paid price if it is present' do
      purchase = create(:purchase, paid_price: 200)

      expect(purchase.price).to eq 200
    end

    it 'uses a one-time coupon just once' do
      coupon = create(:one_time_coupon, amount: 25)
      first_purchase = create(:purchase, coupon: coupon, paid: true)

      expect(first_purchase.price).to eq 11.25

      second_purchase = create(:purchase, coupon: coupon.reload)

      expect(second_purchase.price).to eq 15.00
    end

    it 'it uses PurchasePriceCalculator to calculate the price if paid price is blank' do
      purchase = build(:purchase)
      price_calculator_stub = stub('price_calculator', calculate: true)
      PurchasePriceCalculator.stubs(new: price_calculator_stub)
      coupon = CouponFactory.for_purchase(purchase)

      purchase.price(coupon)

      expect(PurchasePriceCalculator).to have_received(:new).with(purchase, coupon)
      expect(price_calculator_stub).to have_received(:calculate)
    end
  end

  context '#first_name' do
    it "has a first_name that is the first part of name" do
      user = Purchase.new(name: "first last")
      expect(user.first_name).to eq "first"
    end
  end

  context '#last_name' do
    it "has a last_name that is the last part of name" do
      user = Purchase.new(name: "first last")
      expect(user.last_name).to eq "last"
    end
  end

  describe '.paid' do
    it 'returns paid purchases' do
      paid = create(:purchase)
      unpaid = create(:unpaid_purchase)
      Purchase.paid.should == [paid]
    end
  end

  describe '.within_range' do
    it 'returns paid purchases from the given period' do
      outside = create(:purchase, created_at: 40.days.ago)
      unpaid = create(:unpaid_purchase, created_at: 7.days.ago)
      inside = create(:purchase, created_at: 7.days.ago)

      purchases = Purchase.within_range(30.days.ago, Date.yesterday)
      expect(purchases).to include inside
      expect(purchases).not_to include outside
      expect(purchases).not_to include unpaid
    end
  end

  describe '.total_sales_within_range' do
    it 'returns the sum of the paid purchases from the given period' do
      product = create(:product, individual_price: 10)
      outside = create(:purchase, created_at: 40.days.ago, purchaseable: product)
      unpaid = create(:unpaid_purchase, created_at: 7.days.ago, purchaseable: product)
      create(:purchase, created_at: 7.days.ago, purchaseable: product)
      create(:purchase, created_at: 7.days.ago, purchaseable: product)

      total = Purchase.total_sales_within_range(30.days.ago, Date.yesterday)
      expect(total).to eq 20
    end
  end

  context '#status' do
    it 'returns in-progress when it ends today' do
      workshop = create(:workshop, length_in_days: 5)
      Timecop.travel(5.days.ago) do
        @purchase = create_subscriber_purchase_from_purchaseable(workshop)
      end

      expect(@purchase.status).to eq 'in-progress'
    end

    it 'returns in-progress when it ends in future' do
      workshop = create(:workshop, length_in_days: 5)
      purchase = create_subscriber_purchase_from_purchaseable(workshop)

      expect(purchase.status).to eq 'in-progress'
    end

    it 'returns complete when already ended' do
      workshop = create(:workshop, length_in_days: 5)

      Timecop.travel(6.days.ago) do
        @purchase = create_subscriber_purchase_from_purchaseable(workshop)
      end

      expect(@purchase.status).to eq 'complete'
    end
  end

  context 'purchasing as subcriber' do
    it 'does not send a receipt' do
      purchase = create(:unpaid_purchase, payment_method: 'subscription')
      purchase.paid = true
      SendPurchaseReceiptEmailJob.stubs(:enqueue)

      purchase.save!

      SendPurchaseReceiptEmailJob.should have_received(:enqueue).never
    end
  end

  context '#set_as_paid' do
    it 'sets paid properties' do
      purchase = build(:unpaid_purchase)

      purchase.set_as_paid

      purchase.paid.should be_true
      purchase.paid_price.should eq purchase.price
    end

    it 'applies a coupon' do
      coupon = create(:coupon)
      coupon.stubs(:applied)
      purchase = build(:unpaid_purchase, coupon: coupon)

      purchase.set_as_paid

      coupon.should have_received(:applied)
    end
  end

  context "#set_as_unpaid" do
    it 'becomes unpaid' do
      purchase = build_stubbed(:paid_purchase)

      purchase.set_as_unpaid

      purchase.should_not be_paid
    end
  end

  describe '#github_usernames' do
    it 'serializes an array of stripped, non-empty strings' do
      expect(serialize_github_usernames(['', '  one  ', 'two'])).
        to eq(%w(one two))
    end

    it 'serializes nil into an empty array' do
      expect(serialize_github_usernames(nil)).to eq([])
    end

    it 'removes nil entries' do
      expect(serialize_github_usernames([nil, 'name'])).to eq(%w(name))
    end

    def serialize_github_usernames(github_usernames)
      purchase = create(:purchase, github_usernames: github_usernames)
      purchase.reload.github_usernames
    end
  end

  it 'uses its lookup for its param' do
    purchase = build(:purchase, lookup: 'findme')

    purchase.to_param.should eq 'findme'
  end

  it 'generates a lookup' do
    purchase = build(:purchase, lookup: nil)

    purchase.save!
    purchase.lookup.should_not be_nil
  end

  it 'validates the presence of a user when purchasing a plan' do
    expect(build(:plan_purchase)).to validate_presence_of(:user_id)
  end

  describe '#save' do
    it 'tells its purchaseable to fulfill' do
      purchaseable = create(:book)
      purchaseable.stubs(:fulfill)
      purchase = build(:purchase, purchaseable: purchaseable)

      purchase.save!

      expect(purchaseable).
        to have_received(:fulfill).with(purchase, purchase.user)
    end

    it 'fulfills a subscription when purchasing a plan' do
      purchase = build(:plan_purchase)
      fulfillment = stub_subscription_fulfillment(purchase)

      purchase.save!

      fulfillment.should have_received(:fulfill)
    end

    it "doesn't fulfill a subscription when not purchasing a plan" do
      purchase = build(:book_purchase)
      fulfillment = stub_subscription_fulfillment(purchase)

      purchase.save!

      fulfillment.should have_received(:fulfill).never
    end
  end

  describe '#success_url' do
    it 'returns its paypal URL for paypal' do
      controller = stub('controller')
      purchase = build_stubbed(
        :purchase,
        payment_method: 'paypal',
        paypal_url: 'http://example.com/paypal'
      )

      expect(purchase.success_url(controller)).to eq(purchase.paypal_url)
    end

    it 'delegates to its purchaseable' do
      controller = stub('controller')
      after_purchase_url = 'http://example.com/after_purchase'
      product = build_stubbed(:product)
      purchase = build_stubbed(
        :purchase,
        purchaseable: product,
        payment_method: 'stripe'
      )
      product.
        stubs(:after_purchase_url).
        with(controller, purchase).
        returns(after_purchase_url)

      expect(purchase.success_url(controller)).to eq(after_purchase_url)
    end
  end
end

describe Purchase, 'with stripe and a bad card' do
  it "doesn't save" do
    payment = stub('payment', place: false)
    Payments::StripePayment.stubs(:new).returns(payment)
    product = build(:product, individual_price: 15, company_price: 50)
    purchase = build(:purchase, purchaseable: product, payment_method: 'stripe')
    purchase.save.should be_false
  end
end

describe Purchase, 'being paid' do
  it 'sends a receipt' do
    purchase = create(:unpaid_purchase)
    purchase.paid = true
    SendPurchaseReceiptEmailJob.stubs(:enqueue)

    purchase.save!

    SendPurchaseReceiptEmailJob.should have_received(:enqueue).with(purchase.id)
  end
end

describe Purchase, 'with stripe' do
  let(:product) { create(:product, individual_price: 15, company_price: 50) }
  let(:purchase) { build(:purchase, purchaseable: product, payment_method: 'stripe') }
  let(:payment) { stub('payment', :refund => true, :update_user => true, place: true) }
  subject { purchase }

  before do
    Payments::StripePayment.stubs(:new).returns(payment)
  end

  it 'is still a stripe purchase if its coupon discounts 100%' do
    subscription_coupon = stub(apply: 0)
    SubscriptionCoupon.stubs(:new).returns(subscription_coupon)
    purchase = create(:plan_purchase, stripe_coupon_id: 'FREEMONTH')

    expect(purchase).to be_stripe
  end
end

describe Purchase, 'with paypal' do
  let(:product) { create(:product, individual_price: 15, company_price: 50) }
  let(:payment) { stub('payment', place: true, refund: true, complete: true) }

  subject { build(:purchase, purchaseable: product, payment_method: 'paypal') }

  before do
    Payments::PaypalPayment.stubs(:new).with(subject).returns(payment)
    subject.save!
  end

  it 'starts a paypal transaction' do
    payment.should have_received(:place)
    subject.reload.should_not be_paid
  end

  it 'completes a transaction' do
    params = { token: 'TOKEN' }
    subject.complete_payment(params)

    payment.
      should have_received(:complete).with(params)
  end
end

describe Purchase, 'with no price' do
  context 'a valid purchase' do
    let(:product) { create(:product, individual_price: 0) }
    let(:purchase) do
      create(:individual_purchase, purchaseable: product)
    end

    subject { purchase }

    it { should be_free }
    it { should be_paid }
    it { expect(subject.payment_method).to eq 'free' }
  end

  context 'a purchase with an invalid payment method' do
    let(:product) { create(:product, individual_price: 1000) }
    let(:purchase) { build(:purchase, purchaseable: product, payment_method: 'invalid') }
    subject { purchase }
    it { should_not be_valid }
  end
end

describe 'Purchases with various payment methods' do
  it 'includes only stripe payments in the stripe finder' do
    @stripe_purchase = create(:purchase, payment_method: 'stripe')
    @paypal_purchase = create(:purchase, payment_method: 'paypal')

    Purchase.with_stripe_customer_id.should == [@stripe_purchase]
  end
end

describe Purchase, 'after_save' do
  it 'copies purchase info to the purchaser' do
    purchase_info_copier_stub = stub('payment_info_copier', copy_info_to_user: true)
    PurchaseInfoCopier.stubs(new: purchase_info_copier_stub)
    user = create(:user)
    purchase = build(:purchase, user: user)
    expect(purchase_info_copier_stub).to have_received(:copy_info_to_user).never

    purchase.save

    expect(PurchaseInfoCopier).to have_received(:new).with(purchase, purchase.user)
    expect(purchase_info_copier_stub).to have_received(:copy_info_to_user)
  end
end

describe 'Purchases for various emails' do
  context '#by_email' do
    let(:email) { 'user@example.com' }

    before do
      @prev_purchases = [create(:purchase, email: email),
                         create(:purchase, email: email)]
      @other_purchase = create(:purchase)
    end

    it '#by_email' do
      Purchase.by_email(email).should =~ @prev_purchases
      Purchase.by_email(email).should_not include @other_purchase
    end
  end
end

describe Purchase, 'given a purchaser' do
  context 'for a subscription plan' do
    it 'requires a password if there is no user' do
      plan = create(:plan)
      purchase = build(:purchase, purchaseable: plan, user: nil)
      purchase.password = ''

      purchase.save

      expect(purchase.errors[:password]).to include "can't be blank"
    end

    it 'creates a user when saved with a password' do
      plan = create(:plan)
      purchase = build(
        :purchase,
        purchaseable: plan,
        user: nil,
        github_usernames: ['cpytel']
      )
      purchase.password = 'test'

      purchase.save!

      expect(purchase.user).to be_persisted
    end
  end
end

describe Purchase, '#starts_on' do
  it "gets the starts_on from it's purchaseable and it's own created_at" do
    created_at = 1.day.ago
    product = build(:product)
    product.stubs(:starts_on)
    purchase = build(:purchase, purchaseable: product, created_at: created_at)

    purchase.starts_on

    expect(product).to have_received(:starts_on).with(created_at.to_date)
  end
end

describe Purchase, '#ends_on' do
  it "gets the starts_on from it's purchaseable and it's own created_at" do
    created_at = 1.day.ago
    product = build(:product)
    product.stubs(:ends_on)
    purchase = build(:purchase, purchaseable: product, created_at: created_at)

    purchase.ends_on

    expect(product).to have_received(:ends_on).with(created_at.to_date)
  end
end

describe Purchase, '#active?' do
  it "is true when today is between start and end" do
    product = build(:product)
    product.stubs(starts_on: Date.yesterday, ends_on: 4.days.from_now.to_date)
    purchase = build(:purchase, purchaseable: product, created_at: Time.zone.today)

    Timecop.freeze(Time.zone.today) do
      expect(purchase).to be_active
    end

    Timecop.freeze(6.days.from_now) do
      expect(purchase).not_to be_active
    end
  end
end

describe Purchase, '#payment' do
  it 'returns the correct payment using the Payments::Factory' do
    purchase = build(:purchase)
    payment_stub = stub('payment', new: true)
    Payments::Factory.stubs(new: payment_stub)

    purchase.payment

    expect(Payments::Factory).to have_received(:new).with(purchase.payment_method)
  end
end
