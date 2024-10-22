require "aggregate_root"

module Cart
  class Aggregate
    include AggregateRoot

    attr_reader :cart_id

    def initialize(cart_id)
      @cart_id = cart_id
      @items = {}
      @coupon_code = nil
      @discount = 0
    end

    def add_item(item_id:, quantity:, price:)
      apply ItemAdded.new(data: { cart_id:, item_id:, quantity:, price: })
    end

    def update_item_quantity(item_id:, new_quantity:)
      apply ItemQuantityUpdated.new(data: { cart_id:, item_id:, new_quantity: })
    end

    def remove_item(item_id:)
      apply ItemRemoved.new(data: { cart_id:, item_id: })
    end

    def apply_coupon(coupon_code:, discount_amount:)
      apply CouponApplied.new(data: { cart_id:, coupon_code:, discount_amount: })
    end

    def total_price
      @items.sum { |item_id, item| item[:quantity] * item[:price] } - @discount
    end

    on ItemAdded do |event|
      item_id = event.data[:item_id]
      @items[item_id] = {
        quantity: event.data[:quantity],
        price: event.data[:price]
      }
    end

    on ItemQuantityUpdated do |event|
      item_id = event.data[:item_id]
      @items[item_id][:quantity] = event.data[:new_quantity]
    end

    on ItemRemoved do |event|
      item_id = event.data[:item_id]
      @items.delete(item_id)
    end

    on CouponApplied do |event|
      @coupon_code = event.data[:coupon_code]
      @discount = event.data[:discount_amount]
    end
  end
end
