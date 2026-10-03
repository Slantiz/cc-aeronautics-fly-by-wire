-- Each module looks like this
{
	width = 40,
	height = 20,
	init = function(ctx) end,
	draw = function(ctx) end,
	on_touch = function(ctx, x, y) end
}

-- ctx object
{
	mon = mon,
	ox, oy = offset_x, offset_y
	data = data -- shared read-only
	config = config -- shared read/write (persistent)
}
