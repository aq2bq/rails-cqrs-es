Rails.configuration.to_prepare do
  Rails.configuration.event_store = RailsEventStore::JSONClient.new
  Rails.configuration.event_store.tap do |store|
    store.subscribe(OrderProjection, to: [ OrderCompleted ])
  end
end
