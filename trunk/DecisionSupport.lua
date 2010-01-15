-- Validation options
RAIL.Validate.AcquireWhileLocked = {"boolean",false}
RAIL.Validate.Aggressive = {"boolean",false}
RAIL.Validate.AssistOwner = {"boolean",false}
RAIL.Validate.InterceptAlgorithm = {"string","normal"}

-- Interception Routines
do
	RAIL.CalculateIntercept = {
		-- Routine with no interception algorithm
		none = function(target)
			return target.X[0],target.Y[0]
		end,

		-- Sloppy, but processor unintensive
		sloppy = function(target)
			return target.X[-500],target.Y[-500]
		end,

		-- Regular
		normal = function(target)
			-- Get movement speed
			local speed = RAIL.Self:EstimateMove()

			-- Estimate time it'd take to reach the target (if it were standing still)
			local dist = RAIL.Self:DistanceTo(target)
			local ticks = dist/speed

			-- Return the actor's projected position in <ticks> time
			return target.X[-ticks],target.Y[-ticks]
		end,

		-- Should be accurate, but more processor intensive
		advanced = function(target)
			-- TODO: This is all fuckered up. Unusable in current form.
			--		Fix it.


			-- Gather positions, estimated move speeds, movement angles, etc
			local s_x,s_y = RAIL.Self.X[0],RAIL.Self.Y[0]
			local s_speed = RAIL.Self:EstimateMove()
	
			local t_x,t_y = target.X[0],target.Y[0]
			local t_speed,t_move_angle = target:EstimateMove()
	
			local t_to_s_angle,t_dist = GetAngle(t_x,t_y,s_x,s_y)
	
			-- In a triangle,
			--
			--	A
			--	 \
			--	  B-------C
			--
			-- Use Law of Sines to find the optimal movement angle
			--	(Side-Side-Angle: s_speed, t_speed, t_angle_in_triangle)
			--	(Result will be s_angle_in_triangle)
			--
	
			local t_angle_in_triangle = math.abs(t_to_s_angle - t_move_angle)
			if t_angle_in_triangle > 180 then
				t_angle_in_triangle = 360 - t_angle_in_triangle
			end
	
			-- Invert speeds, such that high numbers are faster
			s_speed = 1 / s_speed
			t_speed = 1 / t_speed
	
			-- Solve for s_angle_in_triangle
			local law_of_sines_ratio = s_speed / math.sin(t_angle_in_triangle)
			local s_angle_in_triangle = math.asin(1 / (law_of_sines_ratio / t_speed))
	
			-- Complete the triangle
			local x_angle_in_triangle = 180 - (s_angle_in_triangle + t_angle_in_triangle)
			local x_speed = law_of_sines_ratio * math.sin(x_angle_in_triangle)

			-- Find destination angle on angle side
			local s_to_t_angle = math.mod(t_to_s_angle + 180,360)
			local s_move_angle
	
			if CompareAngle(t_to_s_angle,t_move_angle,-180) then
				s_move_angle = math.mod(s_to_t_angle + s_angle_in_triangle,360)
			else
				s_move_angle = s_to_t_angle - s_angle_in_triangle
				while s_move_angle < 0 do
					s_move_angle = s_move_angle + 360
				end
			end
	
			-- Determine the distance to move
			local radius = t_dist * (s_speed / x_speed)
	
			-- Plot the point
			return PlotCircle(s_x,s_y,s_move_angle,radius)
		end,
	}

	setmetatable(RAIL.CalculateIntercept,{
		__call = function(t,target)
			-- Verify input
			if not RAIL.IsActor(target) then
				return nil
			end

			-- Check for the default intercept algorithm
			local algo = t[string.lower(RAIL.State.InterceptAlgorithm)] or
				t.none
			if type(algo) ~= "function" then
				return nil
			end

			-- Check if the target is moving
			if target.Motion[0] == MOTION_MOVE or type(t.none) ~= "function" then
				return algo(target)
			end

			-- Use none, since it doesn't need to be intercepted
			return t.none(target)
		end,
	})
end

-- Target Selection Routines
do
	-- Base table
	RAIL.SelectTarget = { }

	-- The metatable to run subtables
	local st_metatable = {
		__index = Table,
		__call = function(self,potentials)
			-- Count the number of potential targets
			local n=0
			for i in potentials do
				n=n+1
			end

			-- Sieve the potential list through each of the targeting functions, until 1 or fewer targets are left
			for i,f in ipairs(self) do
				-- Check to see if any potentials are left
				if n < 0 then
					return nil
				end

				-- Call the function
				if type(f) == "function" then
					potentials,n = f(potentials,n)
				end
			end

			-- Check the number of potentials left
			if n > 0 then
				-- Select a target at random from the remaining potentials
				--	(the first returned by the pairs iterator will be used)
				--	Note: if only 1 is left, only 1 can be selected
				local i,k = pairs(potentials)(potentials)
				return k
			else
				-- Return nothing, since we shouldn't target anything
				return nil
			end
		end,
	}

	-- Physical attack targeting
	do
		RAIL.SelectTarget.Attack = Table.New()
		setmetatable(RAIL.SelectTarget.Attack,st_metatable)
	
		-- Assist owner as first priority
		RAIL.SelectTarget.Attack:Append(function(potentials,n)
			-- Check if we can assist our owner
			local owner_target = RAIL.Owner.Target[0]
			if RAIL.State.AssistOwner and potentials[owner_target] ~= nil then
				return { [owner_target.ID] = owner_target },1
			end
	
			-- Don't modify the potential targets
			return potentials,n
		end)
	
		-- Defend owner
		RAIL.SelectTarget.Attack:Append(function(potentials,n)
			-- TODO: this
			return potentials,n
		end)
	
		-- Assist owner's merc/homu
		RAIL.SelectTarget.Attack:Append(function(potentials,n)
			-- Check if we can assist the other (merc or homun)
			if RAIL.Other ~= RAIL.Self then
				local other_target = RAIL.Other.Target[0]
				if RAIL.State.AssistOther and potenitals[other_target] ~= nil then
					return { [other_target.ID] = other_target },1
				end
			end
	
			-- Don't modify the potential targets
			return potentials,n
		end)
	
		-- Defend friends and other
		RAIL.SelectTarget.Attack:Append(function(potentials,n)
			-- Check if we should defend friends
	
			-- TODO: this
			return potentials,n
		end)
	
		-- Sieve out monsters that would be Kill Stolen
		RAIL.SelectTarget.Attack:Append(function(potentials,n)
			local ret,ret_n = {},0
			for id,actor in potentials do
				if not actor:WouldKillSteal() then
					ret[id] = actor
					ret_n = ret_n + 1
				end
			end
			return ret,ret_n
		end)
	
		-- If not aggressive, sieve out monsters that aren't targeting self, other, or owner
		RAIL.SelectTarget.Attack:Append(function(potentials,n)
			-- If aggressive, don't modify the list
			if RAIL.State.Aggressive then
				return potentials,n
			end
	
			for id,actor in potentials do
				local target = actor.Target[0]
				if target ~= RAIL.Owner and target ~= RAIL.Self and target ~= RAIL.Other then
					potentials[id] = nil
					n = n - 1
				end
			end
			return potentials,n
		end)
	
		-- Select the highest priority set of monsters
		RAIL.SelectTarget.Attack:Append(function(potentials,n)
			local ret,ret_n,ret_priority = {},0,0
	
			for id,actor in potentials do
				-- Check this actors priority against the existing list
				local priority = actor.BattleOpts.Priority
	
				-- If priority matches, add this actor to the list
				if priority == ret_priority then
					ret[id] = actor
					ret_n = ret_n + 1
	
				-- If priority is greater, start the list over
				elseif priority > ret_priority then
					ret = { [id] = actor }
					ret_n = 1
					ret_priority = priority
				end
	
			end
	
			return ret,ret_n
		end)
	
		-- Check to see if the previous target is still in this list
		RAIL.SelectTarget.Attack:Append(function(potentials,n)
			-- See if we should "lock" targets
			if RAIL.State.AcquireWhileLocked then
				return potentials,n
			end

			-- [0] will return the most recent (since this decision cycle hasn't processed yet
			local id = RAIL.TargetHistory.Attack[0]

			-- Check if a target was acquired, and is in the list
			if id ~= -1 and potentials[id] ~= nil then
				-- Use the previous target
				return { [id] = potentials[id] },1
			end

			-- It's not, so don't modify the potential list
			return potentials,n
		end)
	end

	-- Chase targeting
	do
		RAIL.SelectTarget.Chase = Table.New()
		setmetatable(RAIL.SelectTarget.Chase,st_metatable)

		-- First, ensure we won't move outside of RAIL.State.MaxDistance
		RAIL.SelectTarget.Chase:Append(function(potentials,n)
			-- MaxDistance is in block tiles, but attack range is in pythagorean distance...
			local max_dist = RAIL.State.MaxDistance

			-- Process each actor
			for id,actor in potentials do
				-- If the actor is within MaxDistance block tiles, this is easy
				if RAIL.Owner:BlocksTo(actor) < max_dist then
					-- Leave the actor in the list
				else
					-- Get the angle from our owner to the actor
					local angle,dist = RAIL.Owner:AngleTo(actor)

					-- If the distance is less than our attack range, we'll be fine
					if dist < RAIL.Self.AttackRange then
						-- Leave the actor in the list
					else
						-- Plot a point that will be closer to the owner
						local x,y = RAIL.Owner:AnglePlot(angle,dist - RAIL.Self.AttackRange)

						-- Check if this point would be inside MaxDistance
						if RAIL.Owner:BlocksTo(x,y) < max_dist then
							-- Leave the actor in the list
						else
							-- Take the actor out of the list, it's outside of range
							potentials[id] = nil
							n = n - 1
						end
					end
				end
			end

			return potentials,n
		end)

		-- Then, chase targeting is mostly the same as attack targeting
		--	Note: Still copy the attack-target locking (GetN() - 1)
		for i=1,RAIL.SelectTarget.Attack:GetN() do
			RAIL.SelectTarget.Chase:Append(RAIL.SelectTarget.Attack[i])
		end

		-- Remove actors that are already in range
		RAIL.SelectTarget.Chase:Append(function(potentials,n)
			for id,actor in potentials do
				-- Calculate distance to the actor
				local dist = RAIL.Self:DistanceTo(actor)

				-- Check if the actor is in range
				--	TODO: Check skill range
				if dist-1 < RAIL.Self.AttackRange then
					-- Remove it
					potentials[id] = nil
					n = n - 1
				end
			end

			return potentials,n
		end)

		-- Find the closest actors
		RAIL.SelectTarget.Chase:Append(function(potentials,n)
			local ret,ret_n,ret_dist = {},0,RAIL.State.MaxDistance+1

			for id,actor in potentials do
				-- Calculate the distance to the actor
				local dist = RAIL.Self:DistanceTo(actor)

				-- Check if the actor is closer than previously checked ones
				if dist < ret_dist then
					-- Create a new return list
					ret = { [id] = actor }
					ret_n = 1
					ret_dist = dist

				-- Check if the actor is just as close
				elseif dist == ret_dist then
					-- Add the actor to the list
					ret[id] = actor
					ret_n = ret_n + 1
				end
			end

			return ret,ret_n
		end)

		-- Check to see if the previous target is still in this list
		RAIL.SelectTarget.Chase:Append(function(potentials,n)
			-- [0] will return the most recent (since this decision cycle hasn't processed yet
			local id = RAIL.TargetHistory.Chase[0]

			-- Check if a target was acquired, and is in the list
			if id ~= -1 and potentials[id] ~= nil then
				-- Use the previous target
				return { [id] = potentials[id] },1
			end

			-- If not in the list, don't modify the list
			return potentials,n
		end)
	end
end