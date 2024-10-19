class CreateOrders < ActiveRecord::Migration[7.2]
  def change
    create_table :orders, id: :uuid do |t|
      t.string :status, null: false, default: "draft", comment: "注文ステータス"

      t.timestamps
    end

    create_table :order_read_models do |t|
      t.string :order_id, null: false, comment: "注文ID", index: { unique: true }
      t.string :status, null: false, comment: "注文ステータス"

      t.timestamps
    end
  end
end
