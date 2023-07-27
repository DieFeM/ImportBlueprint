Scriptname ImportBlueprint:WorkshopScript extends ReferenceAlias

Struct Connection
	Bool IsCable
	ObjectReference RefA
	ObjectReference RefB
EndStruct

Connection[] Property ConnectionsArray Auto Const
Message Property PTSB_InitCounterMessage Auto Const
Message Property PTSB_PowerCounterMessage Auto Const
Message Property PTSB_AskCorpsesMessage Auto Const
Message Property PTSB_AskInitMessage Auto Const
Message Property PTSB_AskAssignMessage Auto Const
GlobalVariable Property PTSB_CounterGlobal Auto Const
GlobalVariable Property PTSB_CounterTotalGlobal Auto Const

Auto State Init
	Event OnWorkshopMode(Bool aStart)
		If aStart
			If CheckBuildAreas()
				GotoState("Done")
				
				Int a = PTSB_AskCorpsesMessage.Show();Remove Corpses
				Int b = PTSB_AskInitMessage.Show();Initialize Refs
				Int c = PTSB_AskAssignMessage.Show();Assign Settlers
				
				InWorkshopModeSave()
				
				If a == 0
					If RemoveCorpses()
						Debug.Notification("Removing Corpses Done")
						InWorkshopModeSave()
					EndIf
				EndIf
				
				If b == 0 || c == 0
					If InitializeRefs(b == 0, c == 0)
						Debug.Notification("Initializing Done")
						InWorkshopModeSave()
					EndIf
				EndIf
								
				If ConnectionsArray.Length > 0
					If SetupPower()
						Debug.Notification("Powering Done")
						InWorkshopModeSave()
					EndIf
				EndIf
				
				GetOwningQuest().Stop()
			EndIf
		EndIf
	EndEvent
EndState

State Done
	Event OnWorkshopMode(Bool aStart)
	EndEvent
EndState

Function InWorkshopModeSave()
	GetReference().StartWorkshop(false)
	Utility.Wait(1)
	Game.RequestSave()
	Utility.Wait(1)
	GetReference().StartWorkshop()
EndFunction

Bool Function RemoveCorpses()
	ObjectReference[] EnableMarkers = GetReference().FindAllReferencesOfType(EnableMarker(), 10000.0)
	Int i = 0
	While i < EnableMarkers.Length
		defaultDisableOnResetIfLocWasCleared ClearableEnableMarker = EnableMarkers[i] As defaultDisableOnResetIfLocWasCleared
		If ClearableEnableMarker && ClearableEnableMarker.GetCurrentLocation() == GetReference().GetCurrentLocation()
			ClearableEnableMarker.GetLinkedRef().Disable()
			ClearableEnableMarker.Disable()
		EndIf
		i += 1
	EndWhile
	
	Keyword[] akActorTypes = GetActorTypes()
	i = 0
	While i < akActorTypes.Length
		ObjectReference[] References = GetReference().FindAllReferencesWithKeyword(akActorTypes[i], 10000.0)
		Int j = 0
		While j < References.Length
			Actor akActor = References[j] As Actor
			If akActor && akActor.IsDead() && !akActor.IsDisabled() && akActor.GetCurrentLocation() == GetReference().GetCurrentLocation()
				akActor.Disable()
			EndIf
			j += 1
		EndWhile
		i += 1
	EndWhile
	
	Return True
EndFunction

Bool Function CheckBuildAreas()
	Bool AllEnabled = True
	ObjectReference[] BuildAreas = GetReference().GetLinkedRefChildren(WorkshopLinkedPrimitive())
	Int i = 0	
	While i < BuildAreas.Length
		If BuildAreas[i].IsDisabled()
			AllEnabled = False
			;There's no "Break" in papyrus, just make 'i' equal to the array length, so that the loop ends.
			i = BuildAreas.Length
		EndIf
		i += 1
	EndWhile
	return AllEnabled
EndFunction

Bool Function SetupPower()
	Int TotalLength = ConnectionsArray.Length
	
	PTSB_CounterGlobal.SetValue(0)
	GetOwningQuest().UpdateCurrentInstanceGlobal(PTSB_CounterGlobal)
	PTSB_CounterTotalGlobal.SetValue(TotalLength)
	GetOwningQuest().UpdateCurrentInstanceGlobal(PTSB_CounterTotalGlobal)
		
	Int i = 0
	While i < TotalLength
		Connection C = ConnectionsArray[i]
		If C.IsCable
			C.RefA.CreateWire(C.RefB)
			UpdateCounter(PTSB_PowerCounterMessage)
			Utility.Wait(0.1)
		EndIf
		i += 1
	EndWhile
	
	i = 0
	While i < TotalLength
		Connection C = ConnectionsArray[i]
		If !C.IsCable
			C.RefA.TransmitConnectedPower()
			UpdateCounter(PTSB_PowerCounterMessage)
			Utility.Wait(0.1)
		EndIf
		i += 1
	EndWhile
	
	Utility.Wait(3)
	PTSB_PowerCounterMessage.UnshowAsHelpMessage()
	Return True
EndFunction

Bool Function InitializeRefs(Bool FixRefs, Bool AutoAssign)	
	ObjectReference[] linkedrefs = GetReference().GetLinkedRefChildren(WorkshopItem())	
	Int TotalLength = linkedrefs.Length
		
	PTSB_CounterGlobal.SetValue(0)
	GetOwningQuest().UpdateCurrentInstanceGlobal(PTSB_CounterGlobal)
	PTSB_CounterTotalGlobal.SetValue(TotalLength)
	GetOwningQuest().UpdateCurrentInstanceGlobal(PTSB_CounterTotalGlobal)
	
	Bool Fixed
	Bool Assigned
	Int i = 0	
	While i < TotalLength
		If linkedrefs[i] && !(linkedrefs[i].GetBaseObject() Is Static) && !linkedrefs[i].IsDisabled() && !linkedrefs[i].IsDeleted()
			If FixRefs
				Fixed = FixRef(linkedrefs[i])
			EndIf
			If AutoAssign
				WorkshopObjectScript WorkshopObject = linkedrefs[i] As WorkshopObjectScript
				If WorkshopObject
					Assigned = AssignSettlerTo(WorkshopObject)
				EndIf
			EndIf
		EndIf
		UpdateCounter(PTSB_InitCounterMessage)
		i += 1
	EndWhile
	Utility.Wait(3)
	PTSB_InitCounterMessage.UnshowAsHelpMessage()
	Return True
EndFunction

Bool Function FixRef(ObjectReference ref)	
	WorkshopObjectScript WorkshopObject = ref As WorkshopObjectScript
	If WorkshopObject
		If !WorkshopObject.HasMultiResource()
			CallWorkshopEvents("OnWorkshopObjectPlaced", ref)
		EndIf
	Else
		If ref As WorkshopNPCScript
			WorkshopParent().AddActorToWorkshopPUBLIC(ref As WorkshopNPCScript, GetReference() As WorkshopScript)
			Return True
		EndIf
		
		Activator ActivatorBase = ref.GetBaseObject() As Activator
		If ActivatorBase && ActivatorBase.IsRadio() && !ref.IsRadioOn()
			ref.SetRadioOn(True)
		EndIf
		
		CallWorkshopEvents("OnWorkshopObjectPlaced", ref)
	EndIf
	Return True
EndFunction

Bool Function AssignSettlerTo(WorkshopObjectScript myObject)
	If myObject.bAllowPlayerAssignment && !myObject.IsBed() && myObject.RequiresActor() && !myObject.IsActorAssigned()
		WorkshopParentScript WorkshopParent = myObject.WorkshopParent
		WorkShopNPCScript UnassignedSettler = GetUnassignedSettler()
		If  myObject.HasMultiResource()
			If !UnassignedSettler
				ActorBase newActorBase
				If myObject.GetBaseObject() Is Flora
					newActorBase = WorkshopParent.WorkshopNPC
				Else
					newActorBase = WorkshopParent.WorkshopNPCGuard
				EndIf
				UnassignedSettler = myObject.PlaceAtMe(newActorBase, abDeleteWhenAble = false) as WorkShopNPCScript
				WorkshopParent.AddActorToWorkshopPUBLIC(UnassignedSettler, GetReference() As WorkshopScript)
			EndIf
			WorkshopParent.TryToAutoAssignActor(GetReference() As WorkshopScript, UnassignedSettler)
		Else
			If !UnassignedSettler
				UnassignedSettler = myObject.PlaceAtMe(WorkshopParent.WorkshopNPC, abDeleteWhenAble = false) as WorkShopNPCScript
			EndIf
			WorkshopParent.AssignActorToObjectPUBLIC(UnassignedSettler, myObject)
		EndIf
	EndIf
	Return True
EndFunction

WorkshopNPCScript Function GetUnassignedSettler()
	WorkshopNPCScript Settler = None
	WorkshopParentScript WP = WorkshopParent()
	ObjectReference[] WorkshopActors = WP.GetWorkshopActors(GetReference() As WorkshopScript)
	Int i = 0
	While i < WorkshopActors.Length
		WorkshopNPCScript theActor = WorkshopActors[i] as WorkShopNPCScript
		If theActor && theActor.bCountsForPopulation && !theActor.bIsWorker
			Settler = theActor
			i = WorkshopActors.Length
		EndIf
		i += 1
	EndWhile
	Return Settler
EndFunction

Function CallWorkshopEvents(String EventName, ObjectReference akRef)
	Var[] params = new Var[1]
	
	params[0] = GetReference()
	akRef.CallFunction(EventName, params)
	
	params[0] = akRef
	GetReference().CallFunction(EventName, params)
EndFunction

Function UpdateCounter(Message Msg)
	Msg.UnshowAsHelpMessage()
	PTSB_CounterGlobal.Mod(1)
	GetOwningQuest().UpdateCurrentInstanceGlobal(PTSB_CounterGlobal)
	Msg.ShowAsHelpMessage(asEvent = "Whistle", afDuration = -1, afInterval = -1, aiMaxTimes = -1, asContext = "", aiPriority = 100)
EndFunction

Keyword[] Function GetActorTypes()
	Keyword[] Types = new Keyword[0]
	Types.Add(Game.GetFormFromFile(0x0002CB73, "Fallout4.esm") As Keyword);Robot
	Types.Add(Game.GetFormFromFile(0x00013795, "Fallout4.esm") As Keyword);Creature
	Types.Add(Game.GetFormFromFile(0x00013794, "Fallout4.esm") As Keyword);NPC
	Types.Add(Game.GetFormFromFile(0x0006D7B6, "Fallout4.esm") As Keyword);SuperMutant
	Types.Add(Game.GetFormFromFile(0x0010C3CE, "Fallout4.esm") As Keyword);Synth
	return Types
EndFunction

Static Function EnableMarker()
	return Game.GetFormFromFile(0x000E4610, "Fallout4.esm") As Static
EndFunction

WorkshopParentScript Function WorkshopParent()
	return Game.GetFormFromFile(0x0002058E, "Fallout4.esm") As WorkshopParentScript
EndFunction

Keyword Function WorkshopItem()
	return WorkshopParent().WorkshopItemKeyword
EndFunction

Keyword Function WorkshopLinkedPrimitive()
	return Game.GetFormFromFile(0x000B91E6, "Fallout4.esm") As Keyword
EndFunction
