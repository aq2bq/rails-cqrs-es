# == Schema Information
#
# Table name: orders
#
#  id                     :uuid             not null, primary key
#  status(注文ステータス) :string           default("draft"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
class Order < ApplicationRecord
  def complete
    update!(status: "completed")
    Rails.configuration.event_store.publish(OrderCompleted.new(data: { order_id: id }))
  end
end
