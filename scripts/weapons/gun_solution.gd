extends RefCounted
class_name GunSolution


## Constant target velocity, inherited shooter velocity and world-space gravity.
## aim_point is a barrel aim reference, NOT the future world-space impact point.
## An empty result means no useful, converged low-flight-time intercept.
static func solve(muzzle: Vector3, shooter_velocity: Vector3, target_position: Vector3,
		target_velocity: Vector3, speed: float, gravity: float,
		useful_range: float = 1500.0, max_range: float = 2500.0) -> Dictionary:
	var relative := target_position - muzzle
	if not muzzle.is_finite() or not shooter_velocity.is_finite() \
			or not target_position.is_finite() or not target_velocity.is_finite() \
			or not is_finite(speed) or not is_finite(gravity) or speed <= 0.0 \
			or not is_finite(useful_range) or not is_finite(max_range) or max_range <= 0.0 \
			or relative.length() <= 0.001 or relative.length() > useful_range:
		return {}
	var velocity := target_velocity - shooter_velocity
	var a := velocity.length_squared() - speed * speed
	var b := 2.0 * relative.dot(velocity)
	var c := relative.length_squared()
	var time := INF
	if absf(a) < 0.001:
		if b < -0.001:
			time = -c / b
	else:
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0.0:
			# Stable quadratic roots, including a target moving nearly at bullet speed.
			var q := -0.5 * (b + (1.0 if b >= 0.0 else -1.0) * sqrt(discriminant))
			if absf(q) > 0.000001:
				for root in [q / a, c / q]:
					if root > 0.0:
						time = minf(time, root)
	if not is_finite(time):
		return {}
	var acceleration := Vector3.DOWN * gravity
	# ponytail: bounded Newton refinement for dogfight low arcs; reject non-convergence
	# rather than offering high-arc artillery solutions. Use quartic roots if those are needed.
	for iteration in 12:
		var offset := relative + velocity * time - acceleration * (0.5 * time * time)
		var error := offset.length() - speed * time
		if absf(error) < 0.001:
			break
		var derivative := offset.normalized().dot(velocity - acceleration * time) - speed
		if absf(derivative) < 0.000001:
			return {}
		time -= error / derivative
		if not is_finite(time) or time <= 0.0:
			return {}
	var aim_offset := relative + velocity * time - acceleration * (0.5 * time * time)
	if absf(aim_offset.length() - speed * time) > 0.01:
		return {}
	var direction := aim_offset.normalized()
	var initial_velocity := direction * speed + shooter_velocity
	# Convex speed makes the trapezoid an upper bound on world travel (Bullet.max_range).
	var travel_bound := (initial_velocity.length() + (initial_velocity + acceleration * time).length()) * time * 0.5
	if travel_bound > max_range:
		return {}
	return {"time": time, "direction": direction, "aim_point": muzzle + aim_offset,
		"intercept_position": target_position + target_velocity * time}


static func assisted_direction(forward: Vector3, solution: Dictionary, cone_degrees: float,
		strength: float) -> Vector3:
	var direction := forward.normalized()
	if solution.is_empty() or direction.angle_to(solution.direction) > deg_to_rad(clampf(cone_degrees, 0.0, 3.0)):
		return direction
	return direction.slerp(solution.direction, clampf(strength, 0.0, 1.0)).normalized()
