module Payments
  # Represents a one-time payment with a zero price, which does not actually
  # need to be charged.
  class FreePayment
    def initialize(purchase)
      @purchase = purchase
    end

    def place
      @purchase.set_as_paid
      true
    end

    def update_user(user)
    end

    def refund
    end
  end
end
