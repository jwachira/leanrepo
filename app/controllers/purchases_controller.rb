class PurchasesController < ApplicationController
  def new
    if current_user_has_active_subscription?
      redirect_for_user_with_subscription
    elsif workshop_purchase?
      redirect_for_non_subscriber_purchasing_a_workshop
    else
      @purchase = build_purchase_with_defaults
    end
  end

  def create
    @purchase =
      PurchaseBuilder.
        new(params: params,
            user: current_user,
            purchases_collection: requested_purchaseable.purchases).
        build

    if @purchase.save
      sign_in_purchasing_user(@purchase)

      redirect_to success_url,
        notice: t('purchase.flashes.success', name: @purchase.purchaseable_name),
        flash: {
          purchase_amount: @purchase.paid_price,
          purchase_name: @purchase.purchaseable_name
        }
    else
      render :new
    end
  end

  def show
    @purchase = Purchase.find_by_lookup!(params[:id])
    @purchaseable = @purchase.purchaseable
    if @purchase.paid?
      render polymorphic_purchaseable_template
    else
      redirect_to @purchaseable
    end
  end

  def index
    @purchases = current_user.ordered_paid_products
  end

  def paypal
    flash.keep
    @purchase = Purchase.find_by_lookup(params[:id])
    @purchase.complete_payment(params)
    redirect_to @purchase
  end

  private

  def current_user_plan_includes_purchaseable?
    current_user_has_active_subscription? &&
      (plan_purchase? || included_in_subscription?)
  end

  def redirect_to_subscriber_purchase_or_default(default_path)
    if plan_purchase?
      flash[:error] = I18n.t('subscriber_purchase.flashes.error')
      redirect_to default_path
    else
      redirect_to subscriber_purchase_url
    end
  end

  def included_in_subscription?
    requested_purchaseable.included_in_plan?(current_user.plan)
  end

  def plan_purchase?
    params[:individual_plan_id].present? || params[:teams_team_plan_id].present?
  end

  def workshop_purchase?
    params[:workshop_id].present?
  end

  def subscriber_purchase_url
    polymorphic_url([:new, :subscriber, requested_purchaseable, :purchase])
  end

  def build_purchase_with_defaults
    purchase = requested_purchaseable.purchases.build(variant: variant)
    PurchasePrepopulater.new(purchase, current_user).prepopulate_with_user_info
    purchase
  end

  def sign_in_purchasing_user(purchase)
    if signed_out? && purchase.user
      sign_in purchase.user
    end
  end

  def success_url
    @purchase.success_url(self)
  end

  def url_after_denied_access_when_signed_out
    sign_up_url
  end

  def polymorphic_purchaseable_template
    "#{@purchaseable.to_partial_path}_purchase_show"
  end

  def variant
    if params[:variant].present?
      params[:variant]
    else
      'individual'
    end
  end

  def redirect_for_user_with_subscription
    if current_user_plan_includes_purchaseable?
      redirect_to_subscriber_purchase_or_default(dashboard_path)
    else
      redirect_for_subscription_without_access
    end
  end

  def redirect_for_subscription_without_access
    redirect_to edit_subscription_path
  end

  def redirect_for_non_subscriber_purchasing_a_workshop
    redirect_to new_subscription_path
  end
end
