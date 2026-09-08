extends Node2D

var life := 0.0
var duration := 0.16
var power := 1.0


func setup(new_power: float) -> void:
	power = max(new_power, 0.25)
	queue_redraw()


func _process(delta: float) -> void:
	life += delta
	var p = clamp(life / duration, 0.0, 1.0)

	scale = Vector2.ONE * lerp(0.72, 1.35, p)
	modulate.a = 1.0 - p

	if life >= duration:
		queue_free()


func _draw() -> void:
	var inner := 6.0 * power
	var outer := 17.0 * power
	var line_width = max(1.5, 2.4 * power)
	var color := Color(1.0, 0.84, 0.48, 1.0)

	# Eight clean radial streaks read well at pixel-art scale without needing
	# another texture asset.
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(
			direction * inner,
			direction * outer,
			color,
			line_width,
			false
		)

	draw_circle(Vector2.ZERO, 3.0 * power, Color(1.0, 0.95, 0.78, 0.95))
