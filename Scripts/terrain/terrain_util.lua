
----------------------------------------------------------------------------------------------------
-- Utility
----------------------------------------------------------------------------------------------------

function forEveryCorner( doThis, padding )
	padding = padding or 0
	for cornerY = g_cellData.bounds.yMin + padding, g_cellData.bounds.yMax - padding + 1 do
		for cornerX = g_cellData.bounds.xMin + padding, g_cellData.bounds.xMax - padding + 1 do
			doThis( cornerX, cornerY )
		end
	end
end

----------------------------------------------------------------------------------------------------

function forEveryCell( doThis, padding )
	padding = padding or 0
	for cellY = g_cellData.bounds.yMin + padding, g_cellData.bounds.yMax - padding do
		for cellX = g_cellData.bounds.xMin + padding, g_cellData.bounds.xMax - padding do
			doThis( cellX, cellY )
		end
	end
end

----------------------------------------------------------------------------------------------------

function getClosestCorner( x, y )
	return math.floor( x / CELL_SIZE + 0.5 ), math.floor( y / CELL_SIZE + 0.5 )
end

----------------------------------------------------------------------------------------------------

function getCell( x, y )
	return math.floor( x / CELL_SIZE ), math.floor( y / CELL_SIZE )
end

----------------------------------------------------------------------------------------------------

function dist2( x0, y0, x1, y1 )
	return ( x0 - x1 )^2 + ( y0 - y1 )^2
end

----------------------------------------------------------------------------------------------------

function distance( x0, y0, x1, y1 )
	return math.sqrt( dist2( x0, y0, x1, y1 ) )
end

----------------------------------------------------------------------------------------------------
