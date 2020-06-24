-- Copyright 2020 Jiří Atanasovský
-- MIT license
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

--made with Solar 2D. https://solar2d.com/


local physics = require ( "physics" )
physics.start ( true )
--True argument prevents sleeping of physics bodies.
--Because other boxes detection is needed to adjust draw order,
--we need to prevent this.

local drawMode = "hybrid" --normal hybrid
physics.setDrawMode ( drawMode )
physics.setGravity( 0,0 )


local function printTable ( tbl, iter )
--[[
Debug purpused.
Prints full table and tables inside this table. Keeps track of iterations to prevent stack overflow.
]]	

	if not ( type ( tbl ) == "table" ) then print ( "WARNING: no table provided to print" ) return false end
	local itr = iter or 0 --this is for recursive function to prevent stack overflow
	if itr < 3 then
		local tabulator = ""
		for i = 1, itr do
			tabulator = tabulator .. "        "
		end
		for k, v in pairs ( tbl ) do
			if type ( v ) == "table" then
				print ( tabulator..tostring(k)..":" )
				printTable ( v, itr + 1 )
				print ( tabulator.."=====" )
			else
				print ( tabulator..tostring(k), tabulator..tostring(v) )
			end
		end
	else
		return false
	end
end

local allBoxes = {}
--Table that will store all boxes information.
--Each index is one box.
--Main properties of each box are: group, face, left, right, top, bottom, order


local function touchBox ( event )
--listener to manage touch on boxes
--creates touch joint to move box around
--removes touch joint on event end ( or cancel )
	local boxGroup = event.target
	
	if ( event.phase == "began" ) then
		-- Set touch focus
		display.getCurrentStage():setFocus( boxGroup )
		
		-- boxGroup.isFixedRotation = true
		-- boxGroup.rotation = 0
		
		boxGroup.touchJoint = physics.newJoint( "touch", boxGroup, boxGroup.x, boxGroup.y )
		boxGroup.touchJoint.maxForce = 5000
		
	elseif ( event.phase == "moved" ) then
		if boxGroup.touchJoint then boxGroup.touchJoint:setTarget ( event.x, event.y ) end
		
	elseif ( event.phase == "ended" or event.phase == "cancelled" ) then
		display.remove ( boxGroup.touchJoint )
		boxGroup.touchJoint = nil
		-- boxGroup.isFixedRotation = false
		
		-- Reset touch focus
		display.getCurrentStage():setFocus( nil )

	end
	return true
end

--===============DRAW FUNCTIONS called from runtime enterFrame listener

--takes table in appropriate format and applies its values to corners or images
--requires allBoxes[i] of box
--tab argument is optional: if not provided, angle 0 is set

--also it detects if there are any boxes on mainSides sides using rayCast
local function manageCorners ( box, tab, mainSides )
	local CornTab = tab or box.corners[1]
	
	--mainSides are two sides that should detect collisions from other boxes. They are different for every
	--box angle interval and are provided in reDrawBoxes function which is enterFrame event listener.
	local cornChange = {} --deformation of corners on main sides will be saved here
	cornChange[1] = {}
	cornChange[2] = {}
	
	for img, valuesTable in pairs ( CornTab ) do
		for prop, value in pairs ( valuesTable ) do
			--apply new values to img: deform its corners according to tab provided by reDrawBoxes()
			box[img]["path"][prop] = value
			
			--now boxes detection part: get coordinats for rayCast
			local newProp = string.sub ( prop, 1,1 ) --only x or y...they are the same at this point (not f.e. x1,y1,x3,y3)
			--check if adjusted side is one of the mainSides that should have rayCast. If so, save its actual values (= deformation)
			--into cornChange table
			if ( box[img] == mainSides[1] ) then
				cornChange[1][newProp] = value
			end	
			if ( box[img] == mainSides[2] ) then
				cornChange[2][newProp] = value
			end
		end
	end
	--restart box list of boxes this box is below
	box.below = nil
	box.below = {}
	
	--cornChange now only contains x and y changes from "normal shape without deformation".
	--We need to get content coordinates for each such deformed corner to be able to rayCast
	for i = 1, 2 do
		local rayCoords = {}

		local X,Y = mainSides[i].x, mainSides[i].y
		local W,H = mainSides[i].widthOriginal/2, mainSides[i].heightOriginal/2
		local cX, cY = cornChange[i].x, cornChange[i].y
		local X1, Y1, X2, Y2
		
		--local coordinates of each box corner are calculated diferently for each side
		if mainSides[i].sideName == "left" then
			X1, Y1, X2, Y2 = -W + cX, -H + cY, -W + cX, H + cY
		elseif mainSides[i].sideName == "right" then
			X1, Y1, X2, Y2 = W + cX, -H + cY, W + cX, H + cY
		elseif mainSides[i].sideName == "top" then
			X1, Y1, X2, Y2 = -W + cX, -H + cY, W + cX, -H + cY
		elseif mainSides[i].sideName == "bottom" then
			X1, Y1, X2, Y2 = -W + cX, H + cY, W + cX, H + cY
		end
		
		--Here we get content coordinates from local coordinates of corners calculated above
		rayCoords[1], rayCoords[2] = mainSides[i]:localToContent ( X1, Y1 ) --x1, y1
		rayCoords[3], rayCoords[4] = mainSides[i]:localToContent ( X2, Y2 )--x2, y2
		
		if drawMode == "hybrid" then
			--because physics engine doesnt show rays in hybrid mode, we will draw lines with same coordinates
			--to show where ray is casted
			mainSides[i].rayLine = display.newLine ( unpack ( rayCoords ) )
			--removed in enterFrame event listener
		end
		local rayMode = "unsorted"
		local rayHits = {}
		
		--we need two rays for each side because otherwise ray could start in detected object which would resolve in no hits
		--they cover each other but they go in oposite directions
		rayHits[1] = physics.rayCast ( rayCoords[1], rayCoords[2], rayCoords[3], rayCoords[4], rayMode )
		rayHits[2] = physics.rayCast ( rayCoords[3], rayCoords[4], rayCoords[1], rayCoords[2], rayMode )
		
		for rh = 1, 2 do
			if rayHits[rh] then --each ray from oposite two
				for h = 1, #rayHits[rh] do
					local thisHit = rayHits[rh][h].object
					if (thisHit.id == box.id) then
						print ( "Box detected itself: self hit!!! :(" )
					elseif ( thisHit.id == 0 ) then --boundery hit
					else
						if not ( table.indexOf( box.below, allBoxes[thisHit.id] ) ) then --check if box is not already in box.below list
							box.below[#box.below+1] = allBoxes[thisHit.id] --save whole box table found by id
						end
					end
				end
			end
		end
	end
end

--rearanges boxes so they are positioned right ( front or back )
--this could use some optimalization or completely different approach
local function rearangeDrawOrder ()
	for b = 1, #allBoxes do
	
		local box = allBoxes[b]
		local maxIter = #allBoxes --Maximum number of iterations. This prevents crash when two boxes detect each other.
		local function orderPlus ( boxToOrder, iter )
			--makes order value + 1 on every box boxToOrder is below, then starts itself with this box as argument and iter + 1.
			if iter < maxIter then
				for i = 1, #boxToOrder.below do
					boxToOrder.below[i].order = boxToOrder.below[i].order + 1
					orderPlus ( boxToOrder.below[i], iter + 1 )
				end
			else
				print ( "OrderPlus too many iterations! Boxes detected each other and caused cycle. :(" )
			end
		end
		orderPlus ( box, 1 )
		
		for i = 1, #box.below do
			--update text
			box.belowText.text = box.belowText.text.." "..box.below[i].id
		end
	end
	
	local boxesToReorder = {}
	for i = 1, #allBoxes do
	--make table with boxes that had order adjusted
	--we dont need all boxes draw order adjusted as boxes that have order 0
	--can stay where they are.
		if allBoxes[i].order > 0 then
			boxesToReorder[#boxesToReorder+1] = allBoxes[i]
		end
	end
	
	--Now we find box with lowest order value and take it to front, then we remove it from
	--boxesToReorder table. We repeat process until there are no more boxes in boxesToReorder table.
	--Because we use toFront on boxes with higher order later, they end up being on top of boxes with lower order.
	while #boxesToReorder > 0 do
		local minOrder = 1000
		local res
		local index
		for i = 1, #boxesToReorder do
			if boxesToReorder[i].order < minOrder then
				res = boxesToReorder[i]
				minOrder = boxesToReorder[i].order
				index = i
			end
		end
		
		res.group:toFront()
		--print ( res.id .. " to front ")
		table.remove ( boxesToReorder, index )
	end

end

--==============CREATE OBJECTS

--background rect
local background = display.newRect ( display.contentCenterX + 30, 500-245+255/2, 1000, 255 )
background:setFillColor ( 1,0,0 )
background.alpha = 0.5

--create squares that act as limits so boxes dont fly off screen
limitsBoxes = {}
--down horizontal
limitsBoxes[1] = display.newRect( 510, 500, 1000, 20 )
--limitsBoxes[1].alpha = 0.01
--up horizontal
limitsBoxes[2] = display.newRect( 510, 245, 1000, 20 )
--limitsBoxes[2].alpha = 0.01
--right vertical
limitsBoxes[3] = display.newRect( 1000, 370, 20, 220 )
--limitsBoxes[3].alpha = 0.01
--left vertical
limitsBoxes[4] = display.newRect( 20, 370, 20, 220 )
--limitsBoxes[4].alpha = 0.01

--add limit to physics
for i = 1, #limitsBoxes do
	physics.addBody( limitsBoxes[i], "static", { friction = 1 } )
	limitsBoxes[i].id = 0
	--this helps identify that box colision wasnt with other box but with boundery
end

--create boxes
for i = 1, 4 do
--[[
We will create group for each box and put all parts of box into this group.
We will add this group later as physics body.
Because of this, all parts of group move together and we have everything in local coordinates.
]]
local mainName, faceWidth, faceHeight, sideWidth, sideHeight

	--different sizes for each box
	if i == 4 then
		mainName = "box_big" --prefix of .png file
		faceWidth, faceHeight = 60/2, 58/2
		sideWidth, sideHeight = 16/2, 12/2
	elseif i == 3 then
		mainName = "box_big"
		faceWidth, faceHeight = 60, 58/2
		sideWidth, sideHeight = 16, 12/2
	else
		mainName = "box_big"
		faceWidth, faceHeight = 60, 58
		sideWidth, sideHeight = 16, 12
	end
	
	allBoxes[i] = {}
	allBoxes[i].id = i
	--id is same for every part of box. It is used to find other parts of the same box in allBoxes table.
	allBoxes[i].group = display.newGroup()
	--Group that is added to physics and all pictures are added to it to rotate and move together.
	--Second option is to use sin and cos functions and move/rotate everything every frame.
	allBoxes[i].group.x = 200 + 200 * ( i - 1)
	allBoxes[i].group.y = 380
	allBoxes[i].group.id = i
	
	--face of box that doesnt deform and only rotates
	allBoxes[i].face = display.newImageRect( allBoxes[i].group, mainName.."_face.png", faceWidth, faceHeight )
	allBoxes[i].face.id = i
	--pictures coordinates are relative to group so 0,0 coordinate is center of the face
	
	local color --color to diferenciate boxes in debug
	if i == 1 then color = { 1,0,0 } elseif i == 2 then color = { 0,1,0 } elseif i == 3 then color = { 0,0,1 } elseif i == 4 then color = {1} end
	
	if drawMode == "hybrid" then		
		allBoxes[i].face:setStrokeColor ( unpack( color ) )
		allBoxes[i].face.strokeWidth = 1
	end
	--debug texts above example
	allBoxes[i].iText = display.newText ( { text = i, x = 100 + 200 * ( i - 1 ), y = 40, fontSize = 18 } )
	allBoxes[i].iText:setFillColor ( unpack ( color ) )
	allBoxes[i].belowText = display.newText ( { text = "below: ", x = 100 + 200 * ( i - 1 ), y = 70, fontSize = 18 } )
	allBoxes[i].angleText = display.newText ( { text = "angle: ", x = 100 + 200 * ( i - 1 ), y = 100, fontSize = 18 } )
	allBoxes[i].inclineText = display.newText ( { text = "incline: ", x = 100 + 200 * ( i - 1 ), y = 130, fontSize = 18 } )
	allBoxes[i].orderText = display.newText ( { text = "order: ", x = 100 + 200 * ( i - 1 ), y = 160, fontSize = 18 } )
	
	--sides of boxes that go trought deformation
	local a = 2 --adjust sides to cover each other
	
	allBoxes[i].left = display.newImageRect( allBoxes[i].group, mainName.."_left.png", sideWidth + a, faceHeight + a )
	allBoxes[i].left.sideName = "left"
	allBoxes[i].left.id = i
	allBoxes[i].left.x = allBoxes[i].face.x - allBoxes[i].face.width/2
	allBoxes[i].left.anchorX = 1
	allBoxes[i].left.widthOriginal = allBoxes[i].left.width
	allBoxes[i].left.heightOriginal = allBoxes[i].left.height
	
	allBoxes[i].right = display.newImageRect( allBoxes[i].group, mainName.."_right.png", sideWidth + a, faceHeight + a )
	allBoxes[i].right.sideName = "right"
	allBoxes[i].right.id = i
	allBoxes[i].right.x = allBoxes[i].face.x + allBoxes[i].face.width/2
	allBoxes[i].right.anchorX = 0
	allBoxes[i].right.widthOriginal = allBoxes[i].right.width
	allBoxes[i].right.heightOriginal = allBoxes[i].right.height

	allBoxes[i].top = display.newImageRect( allBoxes[i].group, mainName.."_top.png", faceWidth + a, sideHeight + a )
	allBoxes[i].top.sideName = "top"
	allBoxes[i].top.id = i
	allBoxes[i].top.y = allBoxes[i].face.y - allBoxes[i].face.height/2
	allBoxes[i].top.anchorY = 1
	allBoxes[i].top.widthOriginal = allBoxes[i].top.width
	allBoxes[i].top.heightOriginal = allBoxes[i].top.height
	
	allBoxes[i].bottom = display.newImageRect( allBoxes[i].group, mainName.."_bottom.png", faceWidth + a, sideHeight + a )
	allBoxes[i].bottom.sideName = "bottom"
	allBoxes[i].bottom.id = i
	allBoxes[i].bottom.y = allBoxes[i].face.y + allBoxes[i].face.height/2
	allBoxes[i].bottom.anchorY = 0
	allBoxes[i].bottom.widthOriginal = allBoxes[i].bottom.width
	allBoxes[i].bottom.heightOriginal = allBoxes[i].bottom.height
	
	--Here comes tables that provide us information about how box sides should be deformed.
	--We need 4 key values for box at 0, 90, 180 and 270 degrees rotation.
	--Values between key values will be calculated on run by reDrawBoxes on enterFrame event.

		local LW = allBoxes[i].left.width
		local LH = allBoxes[i].left.height
		local RW = allBoxes[i].right.width
		local RH = allBoxes[i].right.height
		
		local TH = allBoxes[i].top.height
		local BH = allBoxes[i].bottom.height
		
	allBoxes[i].corners = {}
	
	--	at 0 degrees: initial value, siting on bottom
	allBoxes[i].corners[1] = { 
		left = { x1 = 2*LW, y1 = -TH, x2 = 2*LW, y2 = -BH },
		right = { x4 = 0, y4 = -TH, x3 = 0, y3 = -BH },
		top = { x1 = LW, y1 = 0, x4 = RW, y4 = 0 },
		bottom = { x2 = LW, y2 = -2*BH, x3 = RW, y3 = -2*BH }
	}
		--at 90 degr: laying on right side
	allBoxes[i].corners[2] = { 
		left = { x1 = 0, y1 = -TH, x2 = 0, y2 = -BH },
		right = { x4 = -2*RW, y4 = -TH, x3 = -2*RW, y3 = -BH },
		top = { x1 = -LW, y1 = 0, x4 = -RW, y4 = 0 },
		bottom = { x2 = -LW, y2 = -2*BH, x3 = -RW, y3 = -2*BH },
	}
		--at 180 degr: laying on top side
	allBoxes[i].corners[3] = { 
		left = { x1 = 0, y1 = BH, x2 = 0, y2 = BH },
		right = { x4 = -2*RW, y4 = TH, x3 = -2*RW, y3 = BH },
		top = { x1 = -LW, y1 = 2*TH, x4 = -RW, y4 = 2*TH },
		bottom = { x2 = -RW, y2 = 0, x3 = -RW, y3 = 0 },
	}
		--at 270 degr: laying on left side
		allBoxes[i].corners[4] = { 
		left = { x1 = 2*LW, y1 = TH, x2 = 2*LW, y2 = BH },
		right = { x4 = 0, y4 = TH, x3 = 0, y3 = BH },
		top = { x1 = RW, y1 = 2*TH, x4 = LW, y4 = 2*TH },
		bottom = { x2 = LW, y2 = 0, x3 = RW, y3 = 0 },
	}

end
--=========================PHYSICS BODIES
--Add boxes to physics. We will add whole group containing 5 pictures that put together box.
for i = 1, #allBoxes do
	local thisBox = allBoxes[i]
	
	--Because we added whole group, we need to reshape physics body
	-- so it only covers face of the box.
	local W, H = thisBox.face.width/2, thisBox.face.height/2
	local bodyDesc = { -W,-H, -W,H, W,-H, W,H }
	
	physics.addBody ( thisBox.group, "dynamic", { bounce = 0.05, density = 3, friction = 1, shape = bodyDesc } )
	thisBox.group.isBullet = true
	thisBox.group:addEventListener ( "touch", touchBox )
end

--========================RUNTIME enterFrame LISTENER
local function reDrawBoxes () --each frame do
--This is function that recalculates visual of all boxes in real time and applies it using 
--manageCorners and rearangeDrawOrder functions.
--reDrawBoxes is called on "enterFrame" event.
	for i = 1, #allBoxes do
		
		local thisBox = allBoxes[i]
			thisBox.belowText.text = "below: "
			thisBox.orderText.text = thisBox.order
			thisBox.order = 0
		
			if drawMode == "hybrid" then
				display.remove ( thisBox.left.rayLine )
				display.remove ( thisBox.right.rayLine )
				display.remove ( thisBox.top.rayLine )
				display.remove ( thisBox.bottom.rayLine )
			end
		
		if thisBox.group.isAwake then
			local rotation = allBoxes[i].group.rotation
			local angle = rotation % 360 --value that represents the same visual rotation but in interval 0 to 360
			
			
			local startTable, endTable --key values will be stored here
			local interval --we will calculate values for each interval of 90...this will contain angle value recalculated to this interval
			
			if angle < 90 then
				startTable = thisBox.corners[1]
				endTable = thisBox.corners[2]
				interval = angle
				
				thisBox.top:toFront()
				thisBox.bottom:toBack()
				
			elseif angle < 180 then
				startTable = thisBox.corners[2]
				endTable = thisBox.corners[3]
				interval = angle - 90
				
				thisBox.left:toFront()
				thisBox.right:toBack()
				
			elseif angle < 270 then
				startTable = thisBox.corners[3]
				endTable = thisBox.corners[4]
				interval = angle - 180
				
				thisBox.bottom:toFront()
				thisBox.top:toBack()
				
			elseif angle <= 360 then
				startTable = thisBox.corners[4]
				endTable = thisBox.corners[1]
				interval = angle - 270
				
				thisBox.right:toFront()
				thisBox.left:toBack()
			end
			thisBox.face:toFront()
			
			thisBox.angleText.text = "angle: "..tostring (angle):sub(1,5)
			
			--which parts should detect hits from other objects? Depends on angle...
			local mainSides = {} --sides that should detect other boxes for drawOrder
			if angle <= 45 then
				mainSides[1] = thisBox.top
				mainSides[2] = thisBox.right
			elseif angle <= 135 then
				mainSides[1] = thisBox.left
				mainSides[2] = thisBox.top
			elseif angle <= 225 then
				mainSides[1] = thisBox.bottom
				mainSides[2] = thisBox.left
			elseif angle <= 315 then
				mainSides[1] = thisBox.right
				mainSides[2] = thisBox.bottom
			else
				mainSides[1] = thisBox.top
				mainSides[2] = thisBox.right
			end
			
			local actualTable = {} --actual calculated values for given interval.
			
			for img, valuesTable in pairs ( startTable ) do
				
				actualTable[img] = {}

				for prop, value in pairs ( valuesTable ) do 

					local startTableValue = startTable[img][prop] --value in startTable table
					local endTableValue = endTable[img][prop]
					
					--This is inspired by easing.linear code of corona sdk.
					-- Calculates value that should be applied to corner on given interval.
					local actualTableValue = ( endTableValue - startTableValue )*( interval / 90 ) + startTableValue
					
					--put calculated actualTableValue to table
					actualTable[img][prop] = actualTableValue
				end
			end
			--apply calculated values to thisBox corners
			--also detects hits with other boxes and sets order for each box
			manageCorners ( thisBox, actualTable, mainSides )
		end
	end --end of loop for allBoxes
	rearangeDrawOrder () --take order calculated in manageCorners and rearange drawOrder by it.
end

Runtime:addEventListener( "enterFrame", reDrawBoxes )

--==================DEBUG FUNCTIONS
local pushTimer
local boxToPush = 1
--Regular pushes for testing. Press "t" to toggle.
local function pushIt ()
	allBoxes[boxToPush].group:setLinearVelocity ( 1000, 500 )
	boxToPush = boxToPush + 1
	if boxToPush > #allBoxes then boxToPush = 1 end
end

local function keyPress ( event )
	if event.phase == "up" then
		if event.keyName == "s" then
			physics.pause()
		elseif event.keyName == "d" then
			physics.start()
		elseif event.keyName == "q" then
			allBoxes[1].group:rotate ( -5 )
		elseif event.keyName == "w" then
			allBoxes[1].group:rotate ( 5 )
		elseif event.keyName == "e" then
			allBoxes[2].group:rotate ( -5 )
		elseif event.keyName == "r" then
			allBoxes[2].group:rotate ( 5 )
		elseif event.keyName == "t" then
			if pushTimer then
				timer.cancel ( pushTimer )
				pushTimer = nil
			else
				pushTimer = timer.performWithDelay( 333, pushIt, 0 )
			end
		end
	end
	return true
end

Runtime:addEventListener ( "key", keyPress )