module OrderProjection
  extend self

  def call(event)
    case event
    when OrderCompleted
      order = OrderReadModel.find_or_initialize_by(order_id: event.data[:order_id])
      order.update!(status: "completed")
    else
      Rails.logger.info("Unknown event: #{event.type}")
    end
  end
end
