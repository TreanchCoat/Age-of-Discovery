extends Node
## Global signal hub. Systems emit here; UI and other systems listen.
## Keeps systems decoupled — crucial for swapping in network replication later.

# Time
signal hour_passed(hour: int)
signal day_passed(day: int)

# World / travel
signal port_entered(port_id: StringName)
signal port_left(port_id: StringName)
signal undock_requested()                            # player hit "set sail" in port
signal weather_changed(weather: StringName)

# Discovery
signal discovery_spotted(discovery_id: StringName)   # in range, not yet confirmed
signal discovery_made(discovery_id: StringName)      # confirmed via observation

# Economy
signal trade_executed(port_id: StringName, good_id: StringName, qty: int, total_price: int)
signal prices_updated(port_id: StringName)

# Supplies / voyage
signal supplies_short(ship: ShipState)
signal voyage_event_fired(def: VoyageEventDef)
signal voyage_event_resolved(def: VoyageEventDef)

# City / on foot
## Future facility UIs (shipyard, bank, tavern...) listen for their type here.
signal city_building_interacted(city_id: StringName, building_type: String)
signal city_enter_requested(city_id: StringName)   # market UI "Enter the city"
signal city_left(city_id: StringName)              # player returned to the ship

# Objective (demo guided goal)
signal objective_updated()
signal objective_completed()

# Player
signal fame_changed(category: StringName, new_value: int)
signal gold_changed(new_value: int)
