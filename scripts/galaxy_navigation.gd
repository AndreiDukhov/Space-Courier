extends RefCounted

const Graph = preload("res://scripts/galaxy_graph.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const State = preload("res://scripts/galaxy_state.gd")


static func visible_routes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for route: Dictionary in DataLoader.get_records("routes"):
		if Conditions.is_route_visible(route):
			result.append(route)
	return result


static func plan(destination: String, origin: String = "", boost: bool = false) -> Array[String]:
	if origin.is_empty():
		origin = str(GameState.state.get("current_system", ""))
	return Graph.shortest_path(origin, destination, visible_routes(), GameState.state.get("known_routes", []), OrderManager.active_mass(), boost)


static func path_cost(path: Array[String], limit: String = "expected", boost: bool = false) -> int:
	var total: int = 0
	for route_id: String in path:
		var route: Dictionary = DataLoader.get_record(route_id)
		var known: bool = route_id in GameState.state.get("known_routes", [])
		if limit == "expected" or known:
			total += Graph.estimate(route, OrderManager.active_mass(), known, boost)
		else:
			total += Graph.fuel_cost(float(route["fuel"][limit]), OrderManager.active_mass(), boost)
	return total


static func return_warning(destination: String, outbound: Array[String], boost: bool = false) -> String:
	var return_path: Array[String] = plan(State.INITIAL_SYSTEM, destination, boost)
	if destination != State.INITIAL_SYSTEM and return_path.is_empty():
		return "ui_map_return_unknown"
	var available: float = float(GameState.state.get("ship", {}).get("fuel", {}).get("current", 0.0))
	if path_cost(outbound, "max", boost) + path_cost(return_path, "max", boost) > available:
		return "ui_map_return_fuel"
	return ""
