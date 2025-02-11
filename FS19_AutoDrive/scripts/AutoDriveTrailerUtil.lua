function AutoDrive:handleTrailers(vehicle, dt)
    if vehicle.ad.isActive == true and (vehicle.ad.mode == AutoDrive.MODE_DELIVERTO or vehicle.ad.mode == AutoDrive.MODE_PICKUPANDDELIVER or vehicle.ad.mode == AutoDrive.MODE_UNLOAD) then --and vehicle.isServer == true
        local trailers, trailerCount = AutoDrive:getTrailersOf(vehicle);  		

        if trailerCount == 0 then
            return
        end;        
        
        local leftCapacity = 0;
        local fillLevel = 0;
        for _,trailer in pairs(trailers) do
            for _,fillUnit in pairs(trailer:getFillUnits()) do
                leftCapacity = leftCapacity + trailer:getFillUnitFreeCapacity(_);
                fillLevel = fillLevel + trailer:getFillUnitFillLevel(_);
            end
        end;

        if fillLevel == 0 then
            vehicle.ad.isUnloading = false;
            vehicle.ad.isUnloadingToBunkerSilo = false;
            for _,trailer in pairs(trailers) do
                trailer:setDischargeState(Dischargeable.DISCHARGE_STATE_OFF);
            end;
            
        end;

        if vehicle.ad.mode == AutoDrive.MODE_UNLOAD and vehicle.ad.combineState == AutoDrive.DRIVE_TO_COMBINE then 
            if trailer.spec_cover ~= nil then
                if trailer.spec_cover.state == 0 then
                    local newState = 1    
                    if trailer.spec_cover.state ~= newState and trailer:getIsNextCoverStateAllowed(newState) then
                        trailer:setCoverState(newState,true);
                    end
                end;
            end; 
        end;

        --check distance to unloading destination, do not unload too far from it. You never know where the tractor might already drive over an unloading trigger before that
        local x,y,z = getWorldTranslation(vehicle.components[1].node);
        local destination = AutoDrive.mapWayPoints[vehicle.ad.targetSelected_Unload];        
        if vehicle.ad.mode == AutoDrive.MODE_DELIVERTO then
            destination = AutoDrive.mapWayPoints[vehicle.ad.targetSelected];
        end;
        if destination == nil then
            return;
        end;
        local distance = AutoDrive:getDistance(x,z, destination.x, destination.z);
        if distance < 100 then
            for _,trailer in pairs(trailers) do
                for _,trigger in pairs(AutoDrive.Triggers.tipTriggers) do
                    if distance > 20 and trigger.bunkerSilo == nil then
                        break;
                    end;

                    if trailer.getCurrentDischargeNode == nil then
                        break;
                    end;
                    
                    local dischargeState = trailer:getDischargeState()
                    if dischargeState == Trailer.TIPSTATE_CLOSED and not vehicle.ad.isLoading then
                        vehicle.ad.isPaused = false;
                        vehicle.ad.isUnloading = false;
                    end;

                    if fillLevel == 0 then
                        break;
                    end;

                    local currentDischargeNode = trailer:getCurrentDischargeNode()
                    local distanceToTrigger, bestTipReferencePoint = 0, currentDischargeNode;

                    --find the best TipPoint
                    if not trailer:getCanDischargeToObject(currentDischargeNode) then
                        for i=1,#trailer.spec_dischargeable.dischargeNodes do
                            if trailer:getCanDischargeToObject(trailer.spec_dischargeable.dischargeNodes[i])then
                                trailer:setCurrentDischargeNodeIndex(trailer.spec_dischargeable.dischargeNodes[i]);
                                currentDischargeNode = trailer:getCurrentDischargeNode()
                                break
                            end
                        end
                    end
                    
                    if trailer:getCanDischargeToObject(currentDischargeNode) then
                        trailer:setDischargeState(Dischargeable.DISCHARGE_STATE_OBJECT)
                        vehicle.ad.isPaused = true;
                        vehicle.ad.isUnloading = true;
                    end;

                    if trigger.bunkerSilo ~= nil then                        
                        local currentDischargeNode = trailer:getCurrentDischargeNode().node
                        local x,y,z = getWorldTranslation(currentDischargeNode)
                        local tx,ty,tz = x,y,z+1
                        local x1,z1 = trigger.bunkerSiloArea.sx,trigger.bunkerSiloArea.sz
                        local x2,z2 = trigger.bunkerSiloArea.wx,trigger.bunkerSiloArea.wz
                        local x3,z3 = trigger.bunkerSiloArea.hx,trigger.bunkerSiloArea.hz
                        local trailerInTipRange = MathUtil.hasRectangleLineIntersection2D(x1,z1,x2-x1,z2-z1,x3-x1,z3-z1,x,z,tx-x,tz-z)

                        if trailerInTipRange then
                            trailer:setDischargeState(Dischargeable.DISCHARGE_STATE_GROUND);
                            vehicle.ad.isUnloadingToBunkerSilo = true;
                        end;
                    end;
                    
                    

                    if dischargeState ~= Trailer.TIPSTATE_CLOSED and dischargeState ~= Trailer.TIPSTATE_CLOSING and trigger.bunkerSilo ~= nil then
                        vehicle.ad.isUnloading = true;
                    end;
                end; 
                
                if trailer.spec_cover ~= nil then
                    if trailer.spec_cover.state == 0 then
                        local newState = 1    
                        if trailer.spec_cover.state ~= newState and trailer:getIsNextCoverStateAllowed(newState) then
                            trailer:setCoverState(newState,true);
                        end
                    end;
                end;               
            end;
        end;

        if vehicle.ad.mode == AutoDrive.MODE_PICKUPANDDELIVER then 
            local x,y,z = getWorldTranslation(vehicle.components[1].node);
            local destination = AutoDrive.mapWayPoints[vehicle.ad.targetSelected];
            if destination == nil then
                return;
            end;
            local distance = AutoDrive:getDistance(x,z, destination.x, destination.z);        
            if distance < 20 then
                for _,trailer in pairs(trailers) do
                    for _,trigger in pairs(AutoDrive.Triggers.siloTriggers) do
                        local activate = false;
			            if trigger.fillableObjects ~= nil then
                            for __,fillableObject in pairs(trigger.fillableObjects) do
                                if fillableObject.object == trailer then   
                                activate = true;    
                                end;
                            end;
                        end;
                        if AutoDrive:getSetting("continueOnEmptySilo") and trigger == vehicle.ad.trigger and vehicle.ad.isLoading and vehicle.ad.isPaused and not trigger.isLoading and vehicle.ad.startedLoadingAtTrigger then --trigger must be empty by now. Drive on!
                            vehicle.ad.isPaused = false;
                            vehicle.ad.isUnloading = false;
                            vehicle.ad.isLoading = false;
                        elseif activate == true and not trigger.isLoading and leftCapacity > 0 and AutoDrive:fillTypesMatch(vehicle, trigger, trailer) and trigger:getIsActivatable(trailer) and (not vehicle.ad.startedLoadingAtTrigger) then -- and  and vehicle.ad.isLoading == false                      
                            trigger.autoStart = true
                            trigger.selectedFillType = vehicle.ad.unloadFillTypeIndex   
                            trigger:onFillTypeSelection(vehicle.ad.unloadFillTypeIndex);
                            trigger.selectedFillType = vehicle.ad.unloadFillTypeIndex 
                            g_effectManager:setFillType(trigger.effects, trigger.selectedFillType)
                            trigger.autoStart = false

                            vehicle.ad.isPaused = true;
                            vehicle.ad.isLoading = true;
                            vehicle.ad.startedLoadingAtTrigger = true;
                            vehicle.ad.trigger = trigger;
                        elseif leftCapacity == 0 and vehicle.ad.isPaused then
                            vehicle.ad.isPaused = false;
                            vehicle.ad.isUnloading = false;
                            vehicle.ad.isLoading = false;
                        end;
                    end;

                    if trailer.spec_cover ~= nil then
                        if trailer.spec_cover.state == 0 then
                            local newState = 1    
                            if trailer.spec_cover.state ~= newState and trailer:getIsNextCoverStateAllowed(newState) then
                                trailer:setCoverState(newState,true);
                            end
                        end;
                    end;
                end;
            end;
        end;
    end;
end;

function AutoDrive:fillTypesMatch(vehicle, fillTrigger, workTool,onlyCheckThisFillUnit)
	if fillTrigger ~= nil then
		local typesMatch = false
		local selectedFillType = vehicle.ad.unloadFillTypeIndex or FillType.UNKNOWN;
		local fillUnits = workTool:getFillUnits()
		local checkOnly = onlyCheckThisFillUnit or 0;
		-- go throught the single fillUnits and check:
		-- does the trigger support the tools filltype ?
		-- does the trigger support the single fillUnits filltype ?
		-- does the trigger and the fillUnit match the selectedFilltype or do they ignore it ?
		for i=1,#fillUnits do
			if checkOnly == 0 or i == checkOnly then
				local selectedFillTypeIsNotInMyFillUnit = true
				local matchInThisUnit = false
				for index,_ in pairs(workTool:getFillUnitSupportedFillTypes(i))do 
					--loadTriggers
					if fillTrigger.source ~= nil and fillTrigger.source.providedFillTypes[index] then
						typesMatch = true
						matchInThisUnit =true
					end
					--fillTriggers
					if fillTrigger.sourceObject ~= nil then
						local fillTypes = fillTrigger.sourceObject:getFillUnitSupportedFillTypes(1)  
						if fillTypes[index] then 
							typesMatch = true
							matchInThisUnit =true
						end
					end
					if index == selectedFillType and selectedFillType ~= FillType.UNKNOWN then
						selectedFillTypeIsNotInMyFillUnit = false;
					end
				end
				if matchInThisUnit and selectedFillTypeIsNotInMyFillUnit then
					return false;
				end
			end
		end	
		
		if typesMatch then
			if selectedFillType == FillType.UNKNOWN then
				return true;
			else
				if fillTrigger.source then
					return fillTrigger.source.providedFillTypes[selectedFillType] or false;
				elseif fillTrigger.sourceObject ~= nil then
					local fillType = fillTrigger.sourceObject:getFillUnitFillType(1)  
					return fillType == selectedFillType;
				end
			end		
		end
	end
	return false;
end;

function AutoDrive:getTrailersOf(vehicle)
    AutoDrive.tempTrailers = {};
    AutoDrive.tempTrailerCount = 0;

    if vehicle.getAttachedImplements ~= nil then
        for _, implement in pairs(vehicle:getAttachedImplements()) do
            AutoDrive:getTrailersOfImplement(implement.object);
        end;
    end;
    --print("Vehicle: " .. vehicle.ad.driverName .. " has " .. trailerCount .. " trailers");

    return AutoDrive.tempTrailers, AutoDrive.tempTrailerCount;
end;

function AutoDrive:getTrailersOfImplement(attachedImplement)
    if attachedImplement.getAttachedImplements ~= nil then
        for _, implement in pairs(attachedImplement:getAttachedImplements()) do
            AutoDrive:getTrailersOfImplement(implement.object);
        end;
    end;

    if (attachedImplement.typeDesc == g_i18n:getText("typeDesc_tipper") or attachedImplement.spec_dischargeable ~= nil) and attachedImplement.getFillUnits ~= nil then
        trailer = attachedImplement;
        AutoDrive.tempTrailerCount = 1;
        AutoDrive.tempTrailers[AutoDrive.tempTrailerCount] = trailer;
    end;
    if attachedImplement.vehicleType.specializationsByName["hookLiftTrailer"] ~= nil then     
        if attachedImplement.spec_hookLiftTrailer.attachedContainer ~= nil then    
            trailer = attachedImplement.spec_hookLiftTrailer.attachedContainer.object
            AutoDrive.tempTrailerCount = 1;
            AutoDrive.tempTrailers[AutoDrive.tempTrailerCount] = trailer;
        end;
    end;

    return;
end;
