# RailsでCQRS + イベントーソーシング

## 目次

1. minimum CQRS
2. minimum event-sourcing
3. ディスパッチャー

## 1. minimum CQRS

```ruby
# db/schema.rb
create_table "order_read_models", force: :cascade do |t|
  t.string "order_id", null: false, comment: "注文ID"
  t.string "status", null: false, comment: "注文ステータス"
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
  t.index ["order_id"], name: "index_order_read_models_on_order_id", unique: true
end

create_table "orders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
  t.string "status", default: "draft", null: false, comment: "注文ステータス"
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
end

# app/models/order.rb
class Order < ApplicationRecord
  def complete
    return nil if status != "draft"

    update!(status: "completed")
    Rails.configuration.event_store.publish(OrderCompleted.new(data: { order_id: id }))
  end
end

# app/models/order_read_model.rb
class OrderReadModel < ApplicationRecord
end

# app/events/order_completed.rb
class OrderCompleted < RailsEventStore::Event
end

# config/initializers/event_store.rb
Rails.configuration.to_prepare do
  Rails.configuration.event_store = RailsEventStore::JSONClient.new
  Rails.configuration.event_store.tap do |store|
    store.subscribe(OrderProjection, to: [ OrderCompleted ])
  end
end

# app/projections/order_projection.rb
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

```

### リードモデルができるまで

```ruby
order = Order.create
# => #<Order:0x0000000120cdc2a8 id: "2ddc6745-3904-4adb-ba2c-15b0f57a75bb", status: "draft", created_at: "2024-10-19 03:19:15.870040000 +0000", updated_at: "2024-10-19 03:19:15.870040000 +0000">
order.complete
  TRANSACTION (0.2ms)  BEGIN
  Order Update (2.0ms)  UPDATE "orders" SET "status" = $1, "updated_at" = $2 WHERE "orders"."id" = $3  [["status", "completed"], ["updated_at", "2024-10-19 03:19:22.872956"], ["id", "2ddc6745-3904-4adb-ba2c-15b0f57a75bb"]]
  TRANSACTION (5.5ms)  COMMIT
  TRANSACTION (1.5ms)  BEGIN
  RubyEventStore::ActiveRecord::Event Insert (4.1ms)  INSERT INTO "event_store_events" ("event_id","data","metadata","event_type","created_at","valid_at") VALUES ('f75a7946-92d6-4fe2-b533-49febb297130', '{"order_id":"2ddc6745-3904-4adb-ba2c-15b0f57a75bb"}', '{"correlation_id":"af5d3516-63a3-41c8-a62d-1bb63fa5f7ca","types":{"data":{"order_id":["Symbol","String"]},"metadata":{"correlation_id":["Symbol","String"]}}}', 'OrderCompleted', '2024-10-19 03:19:22.893468', NULL) RETURNING "id"
  TRANSACTION (0.5ms)  COMMIT
  OrderReadModel Load (0.9ms)  SELECT "order_read_models".* FROM "order_read_models" WHERE "order_read_models"."order_id" = $1 LIMIT $2  [["order_id", "2ddc6745-3904-4adb-ba2c-15b0f57a75bb"], ["LIMIT", 1]]
  TRANSACTION (0.2ms)  BEGIN
  OrderReadModel Create (1.1ms)  INSERT INTO "order_read_models" ("order_id", "status", "created_at", "updated_at") VALUES ($1, $2, $3, $4) RETURNING "id"  [["order_id", "2ddc6745-3904-4adb-ba2c-15b0f57a75bb"], ["status", "completed"], ["created_at", "2024-10-19 03:19:22.964622"], ["updated_at", "2024-10-19 03:19:22.964622"]]
  TRANSACTION (0.7ms)  COMMIT
=> #<RailsEventStore::JSONClient:0xb5cc>
```
### イベントが記録されているのを確認

```sql
SELECT * FROM event_store_events;
```

| id   | event_id                             | event_type     | data                                                 | metadata                                                     | created_at                 | valid_at |
| ---- | ------------------------------------ | -------------- | ---------------------------------------------------- | ------------------------------------------------------------ | -------------------------- | -------- |
| 1    | f75a7946-92d6-4fe2-b533-49febb297130 | OrderCompleted | {"order_id": "2ddc6745-3904-4adb-ba2c-15b0f57a75bb"} | {"types": {"data": {"order_id": ["Symbol", "String"]}, "metadata": {"correlation_id": ["Symbol", "String"]}}, "correlation_id": "af5d3516-63a3-41c8-a62d-1bb63fa5f7ca"} | 2024-10-19 03:19:22.893468 |          |


### リードモデルの作成に失敗させると、状態の更新とイベントの記録のみ

```ruby
class OrderReadModel < ApplicationRecord
  before_validation :fail
  def fail = raise "error"
end
```

```ruby
order = Order.create
  TRANSACTION (0.3ms)  BEGIN
  Order Create (3.2ms)  INSERT INTO "orders" ("status", "created_at", "updated_at") VALUES ($1, $2, $3) RETURNING "id"  [["status", "draft"], ["created_at", "2024-10-19 06:16:16.454791"], ["updated_at", "2024-10-19 06:16:16.454791"]]
  TRANSACTION (1.5ms)  COMMIT
=> #<Order:0x0000000120f16898 id: "cbc60dc3-1926-4e29-8021-de375a6adb53", status: "draft", created_at: "2024-10-19 06:16:16.454791000 +0000", updated_at: "2024-10-19 06:16:16.454791000 +0000">
order.complete
  TRANSACTION (0.3ms)  BEGIN
  Order Update (1.0ms)  UPDATE "orders" SET "status" = $1, "updated_at" = $2 WHERE "orders"."id" = $3  [["status", "completed"], ["updated_at", "2024-10-19 06:16:21.464320"], ["id", "cbc60dc3-1926-4e29-8021-de375a6adb53"]]
  TRANSACTION (0.8ms)  COMMIT
  TRANSACTION (0.2ms)  BEGIN
  RubyEventStore::ActiveRecord::Event Insert (0.6ms)  INSERT INTO "event_store_events" ("event_id","data","metadata","event_type","created_at","valid_at") VALUES ('837192ec-5c6f-4dc9-9953-4fe788b1b5ae', '{"order_id":"cbc60dc3-1926-4e29-8021-de375a6adb53"}', '{"correlation_id":"e7fa3fde-c5c1-45dd-8f31-b120ed98544a","types":{"data":{"order_id":["Symbol","String"]},"metadata":{"correlation_id":["Symbol","String"]}}}', 'OrderCompleted', '2024-10-19 06:16:21.488449', NULL) RETURNING "id"
  TRANSACTION (0.7ms)  COMMIT
  OrderReadModel Load (0.6ms)  SELECT "order_read_models".* FROM "order_read_models" WHERE "order_read_models"."order_id" = $1 LIMIT $2  [["order_id", "cbc60dc3-1926-4e29-8021-de375a6adb53"], ["LIMIT", 1]]
app/models/order_read_model.rb:20:in `fail': error (RuntimeError)
        from app/projections/order_projection.rb:8:in `call'
        from app/models/order.rb:13:in `complete'

# コマンド用のモデルとイベントだけが永続化される
Order.count
  Order Count (0.8ms)  SELECT COUNT(*) FROM "orders"
=> 2
# 新たにリードモデルはつくられない
OrderReadModel.count
  OrderReadModel Count (0.6ms)  SELECT COUNT(*) FROM "order_read_models"
=> 1
# イベントが増えている
Rails.configuration.event_store.read.count
  RubyEventStore::ActiveRecord::Event Count (0.9ms)  SELECT COUNT(*) FROM "event_store_events"
=> 2
```

### 状態の更新とリードモデルの作成の整合性を保証したい場合はトランザクション

```ruby
class Order < ApplicationRecord
  def complete
    return nil if status != "draft"

    self.class.transaction do
      update!(status: "completed")
      Rails.configuration.event_store.publish(OrderCompleted.new(data: { order_id: id }))
    end
  end
end
```



## 2. minimum event-sourcing

```ruby
# app/events/cart/item_added.rb
class Cart::ItemAdded < RailsEventStore::Event
end

# app/events/cart/item_removed.rb
class Cart::ItemRemoved < RailsEventStore::Event
end

# app/events/cart/item_quantity_updated.rb
class Cart::ItemQuantityUpdated < RailsEventStore::Event
end

# app/events/cart/coupon_applied.rb
class Cart::CouponApplied < RailsEventStore::Event
end

# app/models/cart/aggregate.rb
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


# app/repositories/cart_repository.rb
require "aggregate_root"

module CartRepository
  class << self
    def load(cart_id)
      stream_name = "#{Cart::Aggregate}$#{cart_id}"
      repository.load(Cart::Aggregate.new(cart_id), stream_name)
    end

    def store(cart)
      stream_name = "#{Cart::Aggregate}$#{cart.cart_id}"
      repository.store(cart, stream_name, expected_version: :auto)
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

```

### カート集約で商品を追加して永続化する

```ruby
cart_id = "xxx"
cart = Cart::Aggregate.new(cart_id)
=> #<Cart::Aggregate:0x000000012a3959b0 @cart_id="xxx", @coupon_code=nil, @discount=0, @items={}, @unpublished_events=[], @version=-1>
cart.add_item(item_id: 1, quantity: 2, price: 3000)
=> [#<Cart::ItemAdded:0x000000012a73e440 @data={:cart_id=>"xxx", :item_id=>1, :quantity=>2, :price=>3000}, @event_id="1246bb2b-e6d2-4740-9677-58a69c6e54eb", @metadata=#<RubyEventStore::Metadata:0x000000012a73e1e8 @h={}>>]
cart.total_price
=> 6000
# パブリッシュされていないイベントを返す
cart.unpublished_events.to_a
=> [#<Cart::ItemAdded:0x000000012a73e440 @data={:cart_id=>"xxx", :item_id=>1, :quantity=>2, :price=>3000}, @event_id="1246bb2b-e6d2-4740-9677-58a69c6e54eb", @metadata=#<RubyEventStore::Metadata:0x000000012a73e1e8 @h={}>>]
# 永続化する
CartRepository.store(cart)
  TRANSACTION (1.0ms)  BEGIN
  RubyEventStore::ActiveRecord::Event Insert (3.6ms)  INSERT INTO "event_store_events" ("event_id","data","metadata","event_type","created_at","valid_at") VALUES ('1246bb2b-e6d2-4740-9677-58a69c6e54eb', '{"cart_id":"xxx","item_id":1,"quantity":2,"price":3000}', '{"correlation_id":"e5037f3e-1d4c-4a24-b510-fd665651f053","types":{"data":{"cart_id":["Symbol","String"],"item_id":["Symbol","Integer"],"quantity":["Symbol","Integer"],"price":["Symbol","Integer"]},"metadata":{"correlation_id":["Symbol","String"]}}}', 'Cart::ItemAdded', '2024-10-22 01:43:14.759519', NULL) RETURNING "id"
  RubyEventStore::ActiveRecord::EventInStream Insert (3.3ms)  INSERT INTO "event_store_events_in_streams" ("stream","position","event_id","created_at") VALUES ('Cart::Aggregate$xxx', 0, '1246bb2b-e6d2-4740-9677-58a69c6e54eb', '2024-10-22 01:43:14.831954') RETURNING "id"
  TRANSACTION (0.9ms)  COMMIT
# パブリッシュされていないイベントは空になる  
cart.unpublished_events.to_a
=> []
```

#### イベントとイベントストリームが記録される

```sql
SELECT * FROM event_store_events;
 id |               event_id               |   event_type    |                                                                                                                                  metadata                                                                                                                                   |                              data                              |         created_at         | valid_at
----+--------------------------------------+-----------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+----------------------------------------------------------------+----------------------------+----------
  1 | 1246bb2b-e6d2-4740-9677-58a69c6e54eb | Cart::ItemAdded | {"types": {"data": {"price": ["Symbol", "Integer"], "cart_id": ["Symbol", "String"], "item_id": ["Symbol", "Integer"], "quantity": ["Symbol", "Integer"]}, "metadata": {"correlation_id": ["Symbol", "String"]}}, "correlation_id": "e5037f3e-1d4c-4a24-b510-fd665651f053"} | {"price": 3000, "cart_id": "xxx", "item_id": 1, "quantity": 2} | 2024-10-22 01:43:14.759519 |


SELECT * FROM event_store_events_in_streams;
 id |       stream        | position |               event_id               |         created_at
----+---------------------+----------+--------------------------------------+----------------------------
  1 | Cart::Aggregate$xxx |        0 | 1246bb2b-e6d2-4740-9677-58a69c6e54eb | 2024-10-22 01:43:14.831954
```

#### イベントストアからも確認できる

```ruby
Rails.configuration.event_store.read.stream("Cart::Aggregate$xxx").to_a
  RubyEventStore::ActiveRecord::EventInStream Load (2.7ms)  SELECT "event_store_events_in_streams".* FROM "event_store_events_in_streams" WHERE "event_store_events_in_streams"."stream" = $1 ORDER BY "event_store_events_in_streams"."id" ASC LIMIT $2  [["stream", "Cart::Aggregate$xxx"], ["LIMIT", 100]]
  RubyEventStore::ActiveRecord::Event Load (0.8ms)  SELECT "event_store_events".* FROM "event_store_events" WHERE "event_store_events"."event_id" = $1  [["event_id", "1246bb2b-e6d2-4740-9677-58a69c6e54eb"]]
=>
[#<Cart::ItemAdded:0x000000012aa3e438
  @data={:price=>3000, :cart_id=>"xxx", :item_id=>1, :quantity=>2},
  @event_id="1246bb2b-e6d2-4740-9677-58a69c6e54eb",
  @metadata=#<RubyEventStore::Metadata:0x000000012aa3e3c0 @h={:correlation_id=>"e5037f3e-1d4c-4a24-b510-fd665651f053", :timestamp=>2024-10-22 01:43:14.759519 UTC, :valid_at=>2024-10-22 01:43:14.759519 UTC}>>]
```

### 集約を更新する

```ruby
# 集約を復元する
cart = CartRepository.load("xxx")
  RubyEventStore::ActiveRecord::EventInStream Load (1.6ms)  SELECT "event_store_events_in_streams".* FROM "event_store_events_in_streams" WHERE "event_store_events_in_streams"."stream" = $1 ORDER BY "event_store_events_in_streams"."id" ASC LIMIT $2  [["stream", "Cart::Aggregate$xxx"], ["LIMIT", 100]]
  RubyEventStore::ActiveRecord::Event Load (1.5ms)  SELECT "event_store_events".* FROM "event_store_events" WHERE "event_store_events"."event_id" = $1  [["event_id", "1246bb2b-e6d2-4740-9677-58a69c6e54eb"]]
=> #<Cart::Aggregate:0x0000000149cf58d8 @cart_id="xxx", @coupon_code=nil, @discount=0, @items={1=>{:quantity=>2, :price=>3000}}, @unpublished_events=[], @version=0>
cart.total_price
=> 6000

cart.apply_coupon(coupon_code: "special_coupon", discount_amount: 1500)
=> [#<Cart::CouponApplied:0x000000014a552af8 @data={:cart_id=>"xxx", :coupon_code=>"special_coupon", :discount_amount=>1500}, @event_id="4bb7a8b0-a47c-4fcf-8fdd-69b5fff8a23f", @metadata=#<RubyEventStore::Metadata:0x000000014a5528f0 @h={}>>]
ec-app(dev)> cart.total_price
=> 4500

# 永続化
CartRepository.store(cart)
  TRANSACTION (1.0ms)  BEGIN
  RubyEventStore::ActiveRecord::Event Insert (1.1ms)  INSERT INTO "event_store_events" ("event_id","data","metadata","event_type","created_at","valid_at") VALUES ('4bb7a8b0-a47c-4fcf-8fdd-69b5fff8a23f', '{"cart_id":"xxx","coupon_code":"special_coupon","discount_amount":1500}', '{"correlation_id":"750c326f-a8ad-490c-963c-f8e03dab234c","types":{"data":{"cart_id":["Symbol","String"],"coupon_code":["Symbol","String"],"discount_amount":["Symbol","Integer"]},"metadata":{"correlation_id":["Symbol","String"]}}}', 'Cart::CouponApplied', '2024-10-22 01:56:02.998420', NULL) RETURNING "id"
  RubyEventStore::ActiveRecord::EventInStream Insert (2.4ms)  INSERT INTO "event_store_events_in_streams" ("stream","position","event_id","created_at") VALUES ('Cart::Aggregate$xxx', 1, '4bb7a8b0-a47c-4fcf-8fdd-69b5fff8a23f', '2024-10-22 01:56:03.036515') RETURNING "id"
  TRANSACTION (2.2ms)  COMMIT
=> 1

# ストリームにイベントが追加されている
Rails.configuration.event_store.read.stream("Cart::Aggregate$xxx").to_a
  RubyEventStore::ActiveRecord::EventInStream Load (0.7ms)  SELECT "event_store_events_in_streams".* FROM "event_store_events_in_streams" WHERE "event_store_events_in_streams"."stream" = $1 ORDER BY "event_store_events_in_streams"."id" ASC LIMIT $2  [["stream", "Cart::Aggregate$xxx"], ["LIMIT", 100]]
  RubyEventStore::ActiveRecord::Event Load (0.9ms)  SELECT "event_store_events".* FROM "event_store_events" WHERE "event_store_events"."event_id" IN ($1, $2)  [["event_id", "1246bb2b-e6d2-4740-9677-58a69c6e54eb"], ["event_id", "4bb7a8b0-a47c-4fcf-8fdd-69b5fff8a23f"]]
=>
[#<Cart::ItemAdded:0x000000014a0d4ad0
  @data={:price=>3000, :cart_id=>"xxx", :item_id=>1, :quantity=>2},
  @event_id="1246bb2b-e6d2-4740-9677-58a69c6e54eb",
  @metadata=#<RubyEventStore::Metadata:0x000000014a0d4aa8 @h={:correlation_id=>"e5037f3e-1d4c-4a24-b510-fd665651f053", :timestamp=>2024-10-22 01:43:14.759519 UTC, :valid_at=>2024-10-22 01:43:14.759519 UTC}>>,
 #<Cart::CouponApplied:0x000000014a0d4530
  @data={:cart_id=>"xxx", :coupon_code=>"special_coupon", :discount_amount=>1500},
  @event_id="4bb7a8b0-a47c-4fcf-8fdd-69b5fff8a23f",
  @metadata=#<RubyEventStore::Metadata:0x000000014a0d4508 @h={:correlation_id=>"750c326f-a8ad-490c-963c-f8e03dab234c", :timestamp=>2024-10-22 01:56:02.99842 UTC, :valid_at=>2024-10-22 01:56:02.99842 UTC}>>]
```



## ディスパッチャー

設定すれば、イベントのハンドリングを制御できる

| **選択基準**           | **同期ハンドラ**                                         | **非同期ハンドラ**                                           |
| ---------------------- | -------------------------------------------------------- | ------------------------------------------------------------ |
| **パフォーマンス**     | 処理がメインスレッドで行われるため、負荷が増すと低下する | バックグラウンド処理で並列化できるため、スケーラブル         |
| **一貫性**             | トランザクションの一部として整合性が保たれる             | 処理の整合性はジョブキューに依存。ロールバックには対応しない |
| **即時性**             | イベントが発生した瞬間に処理される                       | 処理にタイムラグが発生する可能性あり                         |
| **エラーハンドリング** | トランザクション内で対応可能                             | エラーの管理が複雑。ジョブの再試行などが必要                 |
| **ユースケース**       | 重要な状態変更、即時応答が必要な場面                     | メール送信、バッチ処理、重いタスクなど、即時性不要な場面     |



### RubyEventStore::ComposedDispatcher

- リスナー側にperform_laterやperform_asyncがあるかどうかで選択される

```ruby
Rails.configuration.to_prepare do
  Rails.configuration.event_store = RailsEventStore::JSONClient.new(
    dispatcher: RubyEventStore::ComposedDispatcher.new(
    RailsEventStore::ImmediateAsyncDispatcher.new(scheduler: RailsEventStore::ActiveJobScheduler.new),
    RubyEventStore::Dispatcher.new
    )
  )
end
```

### ディスパッチャの違い

- **`RailsEventStore::Dispatcher`**: 同期的にイベントを処理する標準的なディスパッチャ。イベントが発行されたときに、すぐにリスナーの`call`メソッドが実行される。これにより、リクエストや処理が完了する前にすべてのイベント処理も完了する
- **`RailsEventStore::AfterCommitAsyncDispatcher`**: **トランザクションがコミットされた後に**非同期でイベントを処理するディスパッチャ。例えば、データベーストランザクションが成功して確定したあとに、バックグラウンドジョブとしてイベント処理を実行する。失敗した場合はロールバックされるので、無駄なイベント処理を避けられる
- **`RailsEventStore::ImmediateAsyncDispatcher`**: **イベントが発行されると即座に非同期で処理を開始する**ディスパッチャ。トランザクションが完了する前でも、イベントをバックグラウンドジョブとして処理する。これにより、即時に非同期処理が行われるけど、トランザクションの成否には関係なく処理されるため、失敗したトランザクションでもジョブが実行される可能性がある

