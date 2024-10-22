require "aggregate_root"

module CartRepository
  class << self
    def load(cart_id)
      stream_name = "Cart::Aggregate$#{cart_id}"
      repository.load(Cart::Aggregate.new(cart_id), stream_name)
    end

    def store(cart)
      stream_name = "Cart::Aggregate$#{cart.cart_id}"
      repository.store(cart, stream_name)
    end

    private

    def repository
      AggregateRoot::Repository.new(event_store)
    end

    def event_store
      Rails.configuration.event_store
    end
  end
end
