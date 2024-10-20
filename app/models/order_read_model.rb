# == Schema Information
#
# Table name: order_read_models
#
#  id                     :bigint           not null, primary key
#  status(注文ステータス) :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  order_id(注文ID)       :string           not null
#
# Indexes
#
#  index_order_read_models_on_order_id  (order_id) UNIQUE
#
class OrderReadModel < ApplicationRecord
end
