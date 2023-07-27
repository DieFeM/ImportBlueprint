{
	Let you import a settlement to an esp from a Transfer Settlements blueprint.
	------------------------
	Hotkey: Ctrl+Alt+I
}
unit ImportBlueprint;

// Global Vars
var
  TopHeight  :integer;
  PrefixList :TStringList;
  
// TJsonObject casts:

// S string
// I Integer
// L Int64
// U UInt64
// F Double
// D TDateTime
// D Utc TDateTime
// B Boolean
// A TJsonArray
// O TJsonObject

// Castle workshop ref 00066EB6 (for powering reference)

// Automation Tools Functions
{
  ConstructOkCancelButtons:
  A procedure which makes the standard OK and Cancel buttons on a form.
  
  Example usage:
  ConstructOkCancelButtons(frm, pnlBottom, frm.Height - 80);
}
procedure ConstructOkCancelButtons(h: TObject; p: TObject; top: Integer);
var
  btnOk: TButton;
  btnCancel: TButton;
begin
  btnOk := TButton.Create(h);
  btnOk.Parent := p;
  btnOk.Caption := 'OK';
  btnOk.ModalResult := mrOk;
  btnOk.Left := h.Width div 2 - btnOk.Width - 8;
  btnOk.Top := top;
  
  btnCancel := TButton.Create(h);
  btnCancel.Parent := p;
  btnCancel.Caption := 'Cancel';
  btnCancel.ModalResult := mrCancel;
  btnCancel.Left := btnOk.Left + btnOk.Width + 16;
  btnCancel.Top := btnOk.Top;
end;

{
  ConstructLabel:
  A function which can be used to make a label.  Used to make code more compact.
  
  Example usage:
  lbl3 := ConstructLabel(frm, pnlBottom, 65, 8, 360, 'Reference removal options:');
}
function ConstructLabel(h: TObject; p: TObject; top: Integer; left: Integer; width: Integer; height: Integer; s: String): TLabel;
var
  lb: TLabel;
begin
  lb := TLabel.Create(h);
  lb.Parent := p;
  lb.Top := top;
  lb.Left := left;
  lb.Width := width;
  if (height > 0) then
    lb.Height := height;
  lb.Caption := s;
  
  Result := lb;
end;

{
  HexFormID
  Gets the formID of a record as a hexadecimal string.
  
  This is useful for just about every time you want to deal with FormIDs.
  
  Example usage:
  s := HexFormID(e);
}
function HexFormID(e: IInterface): string;
begin
  if ElementExists(e, 'Record Header\FormID') then
    Result := IntToHex(GetLoadOrderFormID(e), 8)
  else
    Result := '00000000';
end;

// End of Automation Tools Functions

function IsHexFormID(const AValue: string): boolean;
var
  regexp: TPerlRegEx;
begin
  regexp := TPerlRegEx.Create;
  try
    regexp.Subject := AValue;
    regexp.RegEx := '^([A-F0-9]+)$';
    Result := regexp.Match;
  finally
    regexp.Free;
  end;
end;

function GetExistingOrNewOverride(e: IInterface; f: IwbFile): IInterface;
var
  i : integer;
begin
  //if the override resides in the file use the existing override from the file
  for i := Pred(OverrideCount(e)) downto 0 do
    if GetFileName(GetFile(OverrideByIndex(e, i))) = GetFileName(f) then
      Result := OverrideByIndex(e, i);
  
  // Otherwise create a new overrie in the file
  if not Assigned(Result) then
    Result := wbCopyElementToFile(e, f, false, false);
end;

function OnlyAlpha(data: string): string;
var
  Regex: TPerlRegEx;
  I:Integer;
begin
  Regex := TPerlRegEx.Create;
  try
    Regex.RegEx := '[^[:alnum:]]';
    Regex.Subject := data;
    Regex.ReplaceAll;
    Result := Regex.Subject;
  finally
    Regex.Free;
  end;
end;

procedure CheckReferencedLinked(ref: IInterface; ToFile: IwbFile);
var
  i, j: integer;
  linkedRef, referenced, el: IInterface;
begin
  ref := MasterOrSelf(ref);
  for i := Pred(ReferencedByCount(ref)) downto 0 do begin
    referenced := ReferencedByIndex(ref, i);
    if Signature(referenced) = 'REFR' then begin
      if ElementExists(referenced, 'Linked References') then begin
        el := ElementByPath(referenced, 'Linked References');
        if Assigned(el) then begin
          j := 0;
          while j < ElementCount(el) do begin
            linkedRef := ElementByIndex(el, j);
            if GetElementEditValues(linkedRef, 'Keyword/Ref') = 'WorkshopStackedItemParentKEYWORD [KYWD:001C5EDD]' then begin
              if GetElementEditValues(linkedRef, 'Ref') = Name(ref) then begin
                SetOverrideDisabledAndDeleted(referenced, ToFile);
              end;
            end;
            Inc(j);
          end;
        end;
      end;
    end;
  end;
end;

procedure SetOverrideDisabledAndDeleted(ref: IInterface; ToFile: IwbFile);
var
  sl: TStringList;
  i: integer;
  refOverride: IInterface;
  Sig: string;
begin
  ref := MasterOrSelf(ref);
  Sig := Signature(BaseRecord(ref));
  if (Sig = 'BOOK') or (Sig = 'NOTE') or (Sig = 'BNDS') then exit;
  if HasKeyword(ref, 'FeaturedItem [KYWD:001B3FAC]') then exit;
  if HasScript(ref, 'YoureSPECIALscript') then exit;
  if HasLocationRefType(ref, '') then exit;
  if (HexFormID(ref) = '000A06A8') then exit;//Croup desk (bedroom key)
  if (HexFormID(ref) = '000A0704') then exit;//Croup dresser (basement key)
  if (HexFormID(ref) = '001A62DE') then exit;//Loot_ToolChest (Dogmeat Quest)
  if (HexFormID(ref) = '0010E130') then exit;//Egret Tours Marina, Phyllis terminal
  if ElementExists(ref, 'Spline Connection') then exit;
  
  sl := TStringList.Create;
  ReportRequiredMasters(ref, sl, false, false);
  i := 0;
  while i < sl.Count do begin
    AddMasterIfMissing(ToFile, sl[i]);
    Inc(i);
  end;
  sl.Free;
  
  refOverride := wbCopyElementToFile(ref, ToFile, false, true);
  if not Assigned(refOverride) then exit;
  SetIsDeleted(refOverride, true);
  SetIsInitiallyDisabled(refOverride, true);
end;

procedure ScrapAll(WorkshopRefFormID: integer; ToFile: IwbFile);
var
  parts, references: TStringList;
  filepath: string;
  pi, i: integer;
  ref: IInterface;
begin
  filepath := ScriptsPath + 'User\' + IntToStr(WorkshopRefFormID) + '.0.log';
  if FileExists(filepath) then begin
    try
      references := TStringList.Create;
      references.LoadFromFile(filepath);
      i := 0;
      while i < references.Count do begin
        parts := TStringList.Create;
        SplitText(references[i], parts);
        if IsHexFormID(parts[0]) then begin
          pi := GetPluginIndex(parts[1]);
          if pi <> -1 then begin
            ref := RecordByFormID(FileByIndex(pi), StrToInt('$' + parts[0]), false);
            if Assigned(ref) then begin
              SetOverrideDisabledAndDeleted(ref, ToFile);
              CheckReferencedLinked(ref, ToFile);
            end;
          end;
        end;
        parts.Free;
        Inc(i);
      end;
    finally
      references.Free;
    end;
  end;
end;

function GetPluginIndex(PluginName: string): integer;
var
  i, pi : integer;
begin
  pi := -1;
  for i := Pred(FileCount) downto 0 do
    if SameText(PluginName, GetFileName(FileByIndex(i))) then begin
      pi := i;
      Break;
    end;
  Result := pi;
end;

function GetRef(PluginIndex: integer; iFormID: integer): IInterface;
var
  PrefixedFormID_Dec: integer;
  PrefixedFormID_Hex: String;
  f: IwbFile;
begin
  f := FileByIndex(PluginIndex);
  PrefixedFormID_Hex := GetLoadOrderPrefix(f) + iFormID;
  PrefixedFormID_Dec := StrToInt('$' + PrefixedFormID_Hex);
  Result := RecordByFormID(f, PrefixedFormID_Dec, true);
end;

procedure AddOrAssign(r: IInterface; container: string; element: string; value: string);
var
  el: IInterface;
begin
  if ElementExists(r, container) then begin
    el := ElementByPath(r, container);
    el := ElementAssign(el, HighInteger, nil, false);
    if Assigned(el) then begin
      SetElementEditValues(el, element, value);
    end;
  end
  else begin
    el := Add(r, container, true);
    if Assigned(el) then begin
      SetElementEditValues(ElementByIndex(el, 0), element, value);
    end;
  end;
end;

function AddMainRecord(f: IInterface; sign: string; edid: string): IInterface;
var
  el: IInterface;
begin
  if ElementExists(f, sign) then
    el := ElementByPath(f, sign)
  else
    el := Add(f, sign, true);
  
  if Assigned(el) then begin
	el := Add(el, sign, true);
    SetElementEditValues(el, 'EDID', edid);
  end;
  result := el;
end;

procedure AddToPowerGrid(workshopRef: IInterface; Node1Ref: IInterface; Node2Ref: IInterface; LineRef: IInterface);
var
  el: IInterface;
begin
  if ElementExists(workshopRef, 'Power Grid') then begin
    el := ElementByPath(workshopRef, 'Power Grid');
    SetElementNativeValues(el, 'XWPG', GetElementNativeValues(el, 'XWPG') + 1);
    el := ElementByPath(el, 'Connections');
    if Assigned(el) then begin
      el := ElementAssign(el, HighInteger, nil, false);
      if Assigned(el) then begin
        if Node1Ref <> nil then
          SetElementEditValues(el, 'Node 1', Name(Node1Ref));
        if Node2Ref <> nil then
          SetElementEditValues(el, 'Node 2', Name(Node2Ref));
        if LineRef <> nil then
          SetElementEditValues(el, 'Line', Name(LineRef));
      end;
    end;
  end
  else begin
    el := Add(workshopRef, 'Power Grid', true);
    if Assigned(el) then begin
      SetElementEditValues(el, 'XWPG', '1');
      el := Add(el, 'XWPN', false);
      if Assigned(el) then begin
        SetElementEditValues(el, 'XWPN\Node 1', Name(Node1Ref));
        SetElementEditValues(el, 'XWPN\Node 2', Name(Node2Ref));
        if LineRef <> nil then
          SetElementEditValues(el, 'XWPN\Line', Name(LineRef));
      end;
    end
    else begin
      AddMessage('Power Grid Could not be added.');
    end;
  end;
end;

procedure SetFlag(elem: IInterface; flagName: string; flagValue: boolean);
var
  sl: TStringList;
  i: Integer;
  f, f2: Cardinal;
begin
  sl := TStringList.Create;
  sl.Text := FlagValues(elem);
  f := GetNativeValue(elem);
  for i := 0 to Pred(sl.Count) do
    if SameText(sl[i], flagName) then begin
      if flagValue then
        f2 := f or (1 shl i)
      else
        f2 := f and not (1 shl i);
      if f <> f2 then SetNativeValue(elem, f2);
      Break;
    end;
  sl.Free;
end;

function GetWorkshopRefDup(workshopRef: IInterface; WorkshopType: integer; ToFile: IwbFile): IInterface;
var
  el, baseObj1, baseObj2, workshopRefDup: IInterface;
  i: integer;
begin
  if WorkshopType = 1 then begin
    AddMessage('Workshop Type: Powered, workshop override to store power grid.');
    workshopRefDup := wbCopyElementToFile(MasterOrSelf(workshopRef), ToFile, false, true);// Copy record for workshop ref as override
  end
  else if (WorkshopType = 0) or (WorkshopType = 2) then begin
    if (WorkshopType = 0) then AddMessage('Workshop Type: Powered in-game by F4SE.');
    if (WorkshopType = 2) then AddMessage('Workshop Type: Not powered.');
    workshopRefDup := MasterOrSelf(workshopRef);// direct access to workshop in master
  end;
  Result := workshopRefDup;
end;

procedure WorkshopAllowMove(baseObj: IInterface; ref: IInterface);
var
  refVMAD, refScripts, refWS, refWSProperties, objVMAD, objScripts, objWS, objWSProperties, prop: IInterface;
  i, j: integer;
  bAllowMoveFound: boolean;
begin
  refVMAD := Add(ref, 'VMAD', true);
  refScripts := ElementByIndex(refVMAD, 2); // Scripts
  refWS := ElementAssign(refScripts, HighInteger, nil, false);
  SetElementEditValues(refWS, 'scriptName', 'workshopnpcscript');
  refWSProperties := ElementByIndex(refWS, 2);
  
  bAllowMoveFound := false;
  
  objVMAD := ElementByPath(baseObj, 'VMAD');
  if Assigned(objVMAD) then begin
    objScripts := ElementByIndex(objVMAD, 2);
    if Assigned(objScripts) then begin
      i := 0;
      while i < ElementCount(objScripts) do begin
        objWS := ElementByIndex(objScripts, i);
        if GetElementEditValues(objWS, 'scriptName') = 'workshopnpcscript' then begin
          objWSProperties := ElementByIndex(objWS, 2);
          j := 0;
          while j < ElementCount(objWSProperties) do begin
            prop := ElementAssign(refWSProperties, HighInteger, ElementByIndex(objWSProperties, j), false);
            if Assigned(prop) then begin
              if GetElementEditValues(prop, 'propertyName') = 'bAllowMove' then begin
                SetElementEditValues(prop, 'Bool', 'True');
                bAllowMoveFound := true;
              end;
            end;
            Inc(j);
          end;
          break;
        end;
        Inc(i);
      end;
    end;
  end;
  
  if bAllowMoveFound = false then begin
    prop := ElementAssign(refWSProperties, HighInteger, nil, false);
    if Assigned(prop) then begin
      SetElementEditValues(prop, 'propertyName', 'bAllowMove');
      SetElementEditValues(prop, 'Type', 'Bool');
      SetElementEditValues(prop, 'Bool', 'True');
    end;
  end;
end;

procedure RemoveHavok(ref: IInterface);
var
  refVMAD, refScripts, refRHS: IInterface;
begin
  refVMAD := Add(ref, 'VMAD', true);
  refScripts := ElementByIndex(refVMAD, 2); // Scripts
  refRHS := ElementAssign(refScripts, HighInteger, nil, false);
  SetElementEditValues(refRHS, 'scriptName', 'DefaultDisableHavokOnLoad');
end;

procedure GetLoadedPlugins(plugins_required: TJsonArray; var loaded_plugins: TStringList); 
var
  pi, i: integer;
begin
  for i := 0 to Pred(plugins_required.Count) do begin
    pi := GetPluginIndex(plugins_required.S[i]);
    if pi = -1 then begin
      AddMessage('***WARNING***: Missing or not loaded file: [' + plugins_required.S[i] + '] related objects will not be imported.');
    end
    else begin
      loaded_plugins.Add(plugins_required.S[i]);
    end;
  end;
end;

function HasKeyword(e: IInterface; Keyword: string): boolean;
var
  KWList: TStringList;
  r: boolean;
  el, baseObj: IInterface;
  i: integer;
begin
  r := false;
  if (Signature(e) = 'REFR') or (Signature(e) = 'ACHR') then baseObj := BaseRecord(e) else baseObj := e;
  
  KWList := TStringList.Create;
  el := ElementByPath(baseObj, 'KWDA');
  if Assigned(el) then begin
    i := 0;
    while i < ElementCount(el) do begin
      KWList.Add(GetEditValue(ElementByIndex(el, i)));
      Inc(i);
    end;
  end;
  
  if KWList.IndexOf(Keyword) > -1 then r := true;
  KWList.Free;
  Result := r;
end;

function CobjIsScrap(e: IInterface): boolean;
var
  r: boolean;
  Link, el, ScrapKey: IInterface;
  i: integer;
begin
  r := false;
  el := ElementByPath(e, 'FNAM');
  ScrapKey := RecordByFormID(FileByIndex(0), StrToInt('$00106D8F'), false);
  if Assigned(el) then begin
    i := 0;
    while i < ElementCount(el) do begin
      Link := LinksTo(ElementByIndex(el, i));
      if (Name(Link) = Name(ScrapKey)) then begin
        r := true;
        break;
      end;
      Inc(i);
    end;
  end;
  
  Result := r;
end;

function HasActorValue(e: IInterface; ActorValue: string): boolean;
var
  AVList: TStringList;
  r: boolean;
  el, baseObj: IInterface;
  i: integer;
begin
  r := false;
  if Signature(e) = 'REFR' then baseObj := BaseRecord(e) else baseObj := e;
  
  AVList := TStringList.Create;
  el := ElementByPath(baseObj, 'PRPS');
  if Assigned(el) then begin
    i := 0;
    while i < ElementCount(el) do begin
      AVList.Add(GetElementEditValues(ElementByIndex(el, i), 'Actor Value'));
      Inc(i);
    end;
  end;
  
  if AVList.IndexOf(ActorValue) > -1 then r := true;
  AVList.Free;
  Result := r;
end;

function HasScript(e: IInterface; script: string): boolean;
var
  el, baseObj: IInterface;
  r: boolean;
  i: integer;
begin
  r := false;
  if Signature(e) = 'REFR' then baseObj := BaseRecord(e) else baseObj := e;
  
  el := ElementByPath(baseObj, 'VMAD');
  if Assigned(el) then begin
    el := ElementByIndex(el, 2); // Scripts
    if Assigned(el) then begin
      i := 0;
      while i < ElementCount(el) do begin
        if GetElementEditValues(ElementByIndex(el, i), 'scriptName') = script then begin
          r := true;
          break;
        end;
        Inc(i);
      end;
    end;
  end;
  Result := r;
end;

function HasLocationRefType(e: IInterface; LocationRefType: string): boolean;
var
  LRTList: TStringList;
  r: boolean;
  el, baseObj: IInterface;
  i: integer;
begin
  r := false;
  if Signature(e) = 'REFR' then begin
    LRTList := TStringList.Create;
    el := ElementByPath(e, 'XLRT');
    if Assigned(el) then begin
      i := 0;
      while i < ElementCount(el) do begin
        LRTList.Add(GetEditValue(ElementByIndex(el, i)));
        Inc(i);
      end;
    end;
    
    if LocationRefType = '' then begin
      if LRTList.Count > 0 then r := true;
    end
    else begin
      if LRTList.IndexOf(LocationRefType) > -1 then r := true;
    end;
    
    LRTList.Free;
  end;
  Result := r;
end;

function IsPickableObject(e: IInterface): boolean;
var
  sign: string;
begin
  sign := Signature(e);
  Result := false;
  if (sign = 'MISC') or 
     (sign = 'WEAP') or 
     (sign = 'ALCH') or 
     (sign = 'AMMO') or 
     (sign = 'ARMO') or 
     (sign = 'BOOK') or 
     (sign = 'MSTT') or 
     (sign = 'NOTE') then 
     Result := true; 
end;

function CreateNewRef(baseObj: IInterface; obj: TJsonObject; workshopRefDup: IInterface; wscell: IInterface; skipLink: boolean): IInterface;
var
  ref, el: IInterface;
  sign, reftype: string;
begin  
  sign := Signature(baseObj);
  
  if (sign = 'NPC_') then reftype := 'ACHR' else reftype := 'REFR';
  
  ref := Add(wscell, reftype, true);
  SetElementEditValues(ref, 'NAME', HexFormID(baseObj));
  SetElementEditValues(ref, 'DATA\Position\X', obj.S['posX']);
  SetElementEditValues(ref, 'DATA\Position\Y', obj.S['posY']);
  SetElementEditValues(ref, 'DATA\Position\Z', obj.S['posZ']);
  SetElementEditValues(ref, 'DATA\Rotation\X', obj.S['rotX']);
  SetElementEditValues(ref, 'DATA\Rotation\Y', obj.S['rotY']);
  SetElementEditValues(ref, 'DATA\Rotation\Z', obj.S['rotZ']);
  
  if (obj.F['Scale'] <> 1.0) and (reftype = 'REFR') then begin    
    el := Add(ref, 'XSCL', true);
    if Assigned(el) then
      SetEditValue(el, obj.S['Scale']);
  end;
  
  if not skipLink and Assigned(WorkshopRefDup) then begin
    el := Add(ref, 'Linked References', true);
    if Assigned(el) then begin
      SetElementEditValues(el, 'XLKR\Keyword/Ref', '00054BA6');
      SetElementEditValues(el, 'XLKR\Ref', Name(workshopRefDup));
    end;
  end;
  
  if sign = 'NPC_' then
    if HasScript(baseObj, 'workshopnpcscript') then
      WorkshopAllowMove(baseObj, ref);
	  
  if IsPickableObject(baseObj) and (obj.I['RemoveHavok'] = 1) then
    RemoveHavok(ref);
  
  Result := ref;
end;

function HasCOBJ(e: IInterface): boolean;
var
  r: boolean;
  i: integer;
  sign: string;
  el: IInterface;
begin
  r := false;
  if ReferencedByCount(e) > 0 then begin
    i := 0;
    while i < ReferencedByCount(e) do begin
      el := ReferencedByIndex(e, i);
      sign := Signature(el);
      
      if (sign = 'COBJ') then begin
        if not CobjIsScrap(el) then begin
          r := true;
          break;
        end;
      end
      else begin 
        if (sign = 'FLST') then begin
         if HasCOBJ(el) then begin
            r := true;
            break;
          end;
        end;
      end;
      
      Inc(i);
    end;
  end;
  Result := r;
end;

function HasScrapCOBJ(e: IInterface): boolean;
var
  r: boolean;
  i: integer;
  sign: string;
  el: IInterface;
begin
  r := false;
  if ReferencedByCount(e) > 0 then begin
    i := 0;
    while i < ReferencedByCount(e) do begin
      el := ReferencedByIndex(e, i);
      sign := Signature(el);
      
      if (sign = 'COBJ') then begin
        if CobjIsScrap(el) then begin
          r := true;
          break;
        end;
      end
      else begin 
        if (sign = 'FLST') then begin
         if HasScrapCOBJ(el) then begin
            r := true;
            break;
          end;
        end;
      end;
      
      Inc(i);
    end;
  end;
  Result := r;
end;

function IsUnscrappableObject(e: IInterface): boolean;
begin
  Result := HasKeyword(e, 'UnscrappableObject [KYWD:001CC46A]');
end;

function GetCounterGlobal(edid: string; f,q: IInterface): IInterface;
var
  QTGL, GLOB: IInterface;	
begin
  GLOB := MainRecordByEditorID(GroupBySignature(f, 'GLOB'), edid);
  if not Assigned(GLOB) then GLOB := AddMainRecord(f, 'GLOB', edid);
  
  if not ElementExists(q, 'Text Display Globals') then begin
    QTGL := Add(q, 'Text Display Globals', true);
    SetEditValue(ElementByIndex(QTGL, 0), Name(GLOB));
  end
  else begin
    QTGL := ElementByPath(q, 'Text Display Globals');
    SetEditValue(ElementAssign(QTGL, HighInteger, nil, false), Name(GLOB));
  end;
  Result := GLOB;
end;

function GetMSG(f: IwbFile; edid, desc: string; qnam: IInterface): IInterface;
var
  MSG: IInterface;
begin	
  MSG := MainRecordByEditorID(GroupBySignature(f, 'MESG'), edid);
  if not Assigned(MSG) then begin
    MSG := AddMainRecord(f, 'MESG', edid);
    SetElementEditValues(MSG, 'DESC', desc);
    SetElementEditValues(MSG, 'QNAM', Name(qnam));
    RemoveElement(MSG, 'DNAM');
  end;
  Result := MSG;
end;

function GetAskMSG(f: IwbFile; edid, desc: string): IInterface;
var
  MSG: IInterface;
begin	
  MSG := MainRecordByEditorID(GroupBySignature(f, 'MESG'), edid);
  if not Assigned(MSG) then begin
    MSG := AddMainRecord(f, 'MESG', edid);
    SetElementEditValues(MSG, 'DESC', desc);
    AddButtonToMessage(MSG, 'Yes');
    AddButtonToMessage(MSG, 'No');
  end;
  Result := MSG;
end;

procedure AddButtonToMessage(MyMessage: IInterface; ButtonText: string);
var
  Menu: IInterface;
begin
  if not ElementExists(MyMessage, 'Menu Buttons') then begin
    Menu := Add(MyMessage, 'Menu Buttons', true);
    SetElementEditValues(ElementByIndex(Menu, 0), 'ITXT', ButtonText);
  end
  else begin
    Menu := ElementByPath(MyMessage, 'Menu Buttons');
    SetElementEditValues(ElementAssign(Menu, HighInteger, nil, false), 'ITXT', ButtonText);
  end;
end;

procedure AddScriptProperty(ScriptProperties: IInterface; sName, sType, sValue: string);
var
  ScriptProperty: IInterface;
begin
  ScriptProperty := ElementAssign(ScriptProperties, HighInteger, nil, false);
  SetElementEditValues(ScriptProperty, 'propertyName', sName);
  SetElementEditValues(ScriptProperty, 'Type', sType);
  SetElementEditValues(ScriptProperty, 'Flags', 'Edited');
  if not (sValue = '') then
    SetElementEditValues(ScriptProperty, 'Value\Object Union\Object v2\FormID', sValue);
end;

function GeneratePoweringQuest(ToFile: IwbFile; bpname: string; WorkshopRef: IInterface): IInterface;
var
  AskMSG1, AskMSG2, AskMSG3, GLB1, GLB2, MSG1, MSG2, Quest, DNAM, Script, Alias, AliasFlags, ANAM, ScriptProperties: IInterface;
begin
  Quest := Add(ToFile, 'QUST', true);
  Quest := Add(Quest, 'QUST', true);
  
  SetEditorID(Quest, 'PTSB_PoweringPhase_' + bpname);
  ANAM := Add(Quest, 'ANAM', true);
  SetEditValue(ANAM, '1');
  
  DNAM := Add(Quest, 'DNAM', true);
  SetFlag(ElementByPath(Quest, 'DNAM - General\Flags'), 'Start Game Enabled', true);
  SetFlag(ElementByPath(Quest, 'DNAM - General\Flags'), 'Unknown 5', true);
  SetFlag(ElementByPath(Quest, 'DNAM - General\Flags'), 'Run Once', true);
  SetElementEditValues(DNAM, 'Form Version', '88');
    
  Alias := Add(Quest, 'Aliases', true);
  Alias := ElementByIndex(Alias, 0);
  SetElementEditValues(Alias, 'ALID - Alias Name', 'WorkshopAlias');
  AliasFlags := Add(Alias, 'FNAM - Flags', true);
  SetFlag(AliasFlags, 'Optional', true);
  SetElementEditValues(Alias, 'ALFR - Forced Reference', Name(WorkshopRef));
  SetElementEditValues(Alias, 'VTCK - Voice Types', 'NULL - Null Reference [00000000]');
  
  GLB1 := GetCounterGlobal('PTSB_CounterGlobal', ToFile, Quest);
  GLB2 := GetCounterGlobal('PTSB_CounterTotalGlobal', ToFile, Quest);
  
  MSG1 := GetMSG(ToFile, 'PTSB_InitCounterMessage_' + bpname, '<Global=PTSB_CounterGlobal>/<Global=PTSB_CounterTotalGlobal> initialized objects.', Quest);
  MSG2 := GetMSG(ToFile, 'PTSB_PowerCounterMessage_' + bpname, '<Global=PTSB_CounterGlobal>/<Global=PTSB_CounterTotalGlobal> powered objects.', Quest);
  
  AskMSG1 := GetAskMSG(ToFile, 'PTSB_AskCorpsesMessage', '<b>Remove Corpses?</b><br><i>Try to disable all corpses from the settlement.</i>');
  AskMSG2 := GetAskMSG(ToFile, 'PTSB_AskInitMessage', '<b>Initialize Objects?</b><br><i>Send events that take place when a workshop object is created.<br><b>It is specially important for those objects that use markers</b>.</i>');
  AskMSG3 := GetAskMSG(ToFile, 'PTSB_AskAssignMessage', '<b>Assign Settlers?</b><br><i>Spawn and assign settlers for each work object.</i>');
    
  Script := Add(Quest, 'VMAD', true);
  
  SetElementEditValues(Script, 'Script Fragments\Unknown', '3');
  
  Script := ElementByIndex(Script, 4);//Aliases
  Script := ElementAssign(Script, HighInteger, nil, false);//Alias
  
  SetElementEditValues(Script, 'Object Union\Object v2\FormID', Name(Quest));
  SetElementEditValues(Script, 'Object Union\Object v2\Alias', '000 WorkshopAlias');
  Script := ElementByIndex(Script, 3);//Alias Scripts
  Script := ElementAssign(Script, HighInteger, nil, false);//Script #1
  SetElementEditValues(Script, 'ScriptName', 'ImportBlueprint:WorkshopScript');
  ScriptProperties := ElementByIndex(Script, 2);
  
  AddScriptProperty(ScriptProperties, 'ConnectionsArray', 'Array of Struct', '');
  AddScriptProperty(ScriptProperties, 'PTSB_InitCounterMessage', 'Object', Name(MSG1));
  AddScriptProperty(ScriptProperties, 'PTSB_PowerCounterMessage', 'Object', Name(MSG2));
  AddScriptProperty(ScriptProperties, 'PTSB_AskCorpsesMessage', 'Object', Name(AskMSG1));
  AddScriptProperty(ScriptProperties, 'PTSB_AskInitMessage', 'Object', Name(AskMSG2));
  AddScriptProperty(ScriptProperties, 'PTSB_AskAssignMessage', 'Object', Name(AskMSG3));
  AddScriptProperty(ScriptProperties, 'PTSB_CounterGlobal', 'Object', Name(GLB1));
  AddScriptProperty(ScriptProperties, 'PTSB_CounterTotalGlobal', 'Object', Name(GLB2));
  
  Result := Quest;
end;

procedure AddConnectionToQuest(Quest: IInterface; IsCable: integer; RefA: IInterface; RefB: IInterface);
var
  ArrayOfStructs, NewStruct, Member: IInterface;
begin
  ArrayOfStructs := ElementByPath(Quest, 'VMAD\Aliases\Alias\Alias Scripts\Script\Properties\Property\Value\Array of Struct');
  If Assigned(ArrayOfStructs) then begin
    NewStruct := ElementAssign(ArrayOfStructs, HighInteger, nil, false);
    
    Member := ElementAssign(NewStruct, HighInteger, nil, false);
    SetElementEditValues(Member, 'memberName', 'IsCable');
    SetElementEditValues(Member, 'Type', 'Bool');
    SetElementEditValues(Member, 'Flags', 'Edited');
    SetElementNativeValues(Member, 'Bool', IsCable);
    
    Member := ElementAssign(NewStruct, HighInteger, nil, false);
    SetElementEditValues(Member, 'memberName', 'RefA');
    SetElementEditValues(Member, 'Type', 'Object');
    SetElementEditValues(Member, 'Flags', 'Edited');
    SetElementEditValues(Member, 'Value\Object Union\Object v2\FormID', Name(RefA));
    
    If Assigned(RefB) then begin
      Member := ElementAssign(NewStruct, HighInteger, nil, false);
      SetElementEditValues(Member, 'memberName', 'RefB');
      SetElementEditValues(Member, 'Type', 'Object');
      SetElementEditValues(Member, 'Flags', 'Edited');
      SetElementEditValues(Member, 'Value\Object Union\Object v2\FormID', Name(RefB));
    end;
  end;
end;

procedure ConnectCables(items: TJsonArray; i: integer; ObjRefs: TStringList; workshopRefDup: IInterface; wscell: IInterface; ToFile: IwbFile; Quest: IInterface; WorkshopType: integer);
var
  ConnectedObjects: TStringList;
  obj: TJsonObject;
  ConnectedObjectIndex, j: integer;
  el, ref, refA, refB: IInterface;
begin
  obj := items.O[i];
  
  ConnectedObjects := TStringList.Create;
  SplitText(obj.S['ConnectedObjects'], ConnectedObjects);
  
  refA := RecordByFormID(ToFile, StrToInt('$' + ObjRefs[i]), true);
  
  // Loop Connected Objects
  for j := 0 to Pred(ConnectedObjects.Count) do begin
    ConnectedObjectIndex := StrToInt(ConnectedObjects[j]);
    
    // Skip if Connected Object has a lower Index than this object
    if ConnectedObjectIndex < i then continue;
    
    // Skip if connected object is out of items bounds
    if ConnectedObjectIndex >= items.Count then continue;
    
    // Skip if connected object doesn't have a reference
    if not IsHexFormID(ObjRefs[ConnectedObjectIndex]) then continue;
        
    // Get Connected Object Ref
    refB := RecordByFormID(ToFile, StrToInt('$' + ObjRefs[ConnectedObjectIndex]), true);
    
    if WorkshopType = 0 then
      AddConnectionToQuest(Quest, 1, refA, refB)
    else begin 
      // Create Spline
      ref := Add(wscell, 'REFR', true);
      SetElementEditValues(ref, 'NAME', '0001D971');
      SetElementNativeValues(ref, 'DATA\Position\X', StrToFloat(obj.S['posX']) + ((GetElementNativeValues(refB, 'DATA\Position\X') - GetElementNativeValues(refA, 'DATA\Position\X'))/2));
      SetElementNativeValues(ref, 'DATA\Position\Y', StrToFloat(obj.S['posY']) + ((GetElementNativeValues(refB, 'DATA\Position\Y') - GetElementNativeValues(refA, 'DATA\Position\Y'))/2));
      SetElementNativeValues(ref, 'DATA\Position\Z', StrToFloat(obj.S['posZ']) + ((GetElementNativeValues(refB, 'DATA\Position\Z') - GetElementNativeValues(refA, 'DATA\Position\Z'))/2));
      SetElementEditValues(ref, 'DATA\Rotation\X', '0.0');
      SetElementEditValues(ref, 'DATA\Rotation\Y', '0.0');
      SetElementEditValues(ref, 'DATA\Rotation\Z', '0.0');
      
      // Link Spline ref to workshop
      el := Add(ref, 'Linked References', true);
      if Assigned(el) then begin
        SetElementEditValues(el, 'XLKR\Keyword/Ref', '00054BA6');
        SetElementEditValues(el, 'XLKR\Ref', Name(workshopRefDup));
      end;
      
      // Set Spline Values
      el := Add(ref, 'XBSD', true);
      if Assigned(el) then begin
        // Slack
        SetEditValue(ElementByIndex(el, 0), '0.051149');
        // Thickness
        SetEditValue(ElementByIndex(el, 1), '1.500000');
        // ? Other point Relative X
        SetNativeValue(ElementByIndex(el, 2), (GetElementNativeValues(refB, 'DATA\Position\X') - GetElementNativeValues(refA, 'DATA\Position\X'))/2);
        // ? Other point Relative Y
        SetNativeValue(ElementByIndex(el, 3), (GetElementNativeValues(refB, 'DATA\Position\Y') - GetElementNativeValues(refA, 'DATA\Position\Y'))/2);
        // ? Other point Relative Z
        SetNativeValue(ElementByIndex(el, 4), (GetElementNativeValues(refB, 'DATA\Position\Z') - GetElementNativeValues(refA, 'DATA\Position\Z'))/2);
        // Detached End
        SetEditValue(ElementByIndex(el, 5), 'False');
      end;
      
      // Set Spline Connections
      AddOrAssign(ref, 'Spline Connection', 'Ref', Name(refA));
      AddOrAssign(ref, 'Spline Connection', 'Ref', Name(refB));
      AddOrAssign(refA, 'Spline Connection', 'Ref', Name(ref));
      AddOrAssign(refB, 'Spline Connection', 'Ref', Name(ref));
      
      // Setup Grid
      AddToPowerGrid(workshopRefDup, refA, refB, ref);
    end;
  // End Loop Connected Objects
  end;
  ConnectedObjects.Free;
end;

function GetLoadOrderPrefix(f: IwbFile): string;
var
  LO: Integer;
begin
  LO := GetLoadOrder(f);
  Result := PrefixList[LO];
end;

procedure SplitText(const s: String; aList: TStringList);
begin
  aList.Delimiter := '|';
  aList.StrictDelimiter := true; // Spaces excluded from being a delimiter
  aList.DelimitedText := s;
end;

procedure MyCustomSort(var List: TStringList);
var
  cur, i: integer;
  token: string;
  parts, sl: TStringList;
begin
  sl := TStringList.Create;

  for i := 0 to Pred(List.Count) do begin
    cur := StrToInt(Copy(List[i], 1, Pos('\', List[i]) - 1));
    token := format('%.5d', [cur]);
    sl.Add(token + '|' + List[i]);
  end;

  sl.Sort;
  List.Free;
  List := TStringList.Create;

  for i := 0 to Pred(sl.Count) do begin
    parts := TStringList.Create;
    SplitText(sl[i], parts);
    List.Add(parts[1]);
  end;

  sl.Free;
  parts.Free;
end;

procedure GenerateBlueprintList(var List: TStringList);
var
  i: integer;
  slContainers, slAssets: TStringList;
begin
  slContainers := TStringList.Create;
  slAssets := TStringList.Create;
  
  ResourceContainerList(slContainers);
  
  for i := 0 to Pred(slContainers.Count) do
    if ExtractFileName(slContainers[i]) = '' then
      ResourceList(slContainers[i], slAssets);
  
  slAssets.Sort;
  wbRemoveDuplicateStrings(slAssets);
  
  for i := 0 to Pred(slAssets.Count) do
    if ContainsText(slAssets[i], 'F4SE\Plugins\TransferSettlements\blueprints') then
      if SameText(ExtractFileExt(slAssets[i]), '.json') then
        List.Add(StringReplace(slAssets[i], 'F4SE\Plugins\TransferSettlements\blueprints\', '', [rfReplaceAll, rfIgnoreCase]));
  
  if List.Count > 0 then MyCustomSort(List);
  
  slAssets.Free;
  slContainers.Free;
end;

procedure GenerateEspList(var List: TStringList);
var
  i: integer;
begin
  List.Add('<New File>');
  for i := Pred(FileCount) downto 0 do
    if SameText(ExtractFileExt(GetFileName(FileByIndex(i))), '.esp') then
      List.Add(GetFileName(FileByIndex(i)));
end;

procedure GenerateWorkshopTypeList(var List: TStringList);
begin
  List.Add('Powered In-Game By F4SE (Best results, Script Extender required)');
  List.Add('Override Record (Only new game, saved game = no power. Cables not good but power OK)');
  List.Add('Not Powered (Best compatibility, manual re-snap and cabling required)');
end;

procedure CreateSelector(var cbFiles: TComboBox; frm: TForm; title: string; List: TStringList; index: integer);
var
  lbl: TLabel;
  i: integer;
begin
  TopHeight := TopHeight + 30;
  lbl := ConstructLabel(frm, frm, TopHeight, 15, 0, 0, 'Select ' + title + ':');
  
  cbFiles.Parent := frm;
  TopHeight := lbl.Top + lbl.Height + 5;
  cbFiles.Top := TopHeight;
  cbFiles.Left := 15;
  cbFiles.Width := 500;
  cbFiles.Style := csDropDownList;
  
  for i := 0 to Pred(List.Count) do
    cbFiles.Items.Add(List[i]);
  
  cbFiles.ItemIndex := index;
end;

procedure CreateCheckBox(var cbItem: TCheckBox; frm: TForm; IsChecked: boolean; title, question: string);
var
  lbl: TLabel;
begin
  TopHeight := TopHeight + 30;
  cbItem.Parent := frm;
  cbItem.Top := TopHeight;
  cbItem.Left := 15;
  cbItem.Width := 500;
  cbItem.Caption := title;
  cbItem.Checked := IsChecked;
  TopHeight := TopHeight + 20;
  lbl := ConstructLabel(frm, frm, TopHeight, 30, 0, 0, question);
  lbl.Font.Size := 7;
  lbl.Font.Style := [fsBold];
  TopHeight := TopHeight + lbl.Height;
end;

procedure InitializePrefixList();
var
  r, i, esl, espm : integer;
  f: IwbFile;
begin
  esl := 0;
  espm := 0;
  PrefixList := TStringList.Create;
  for i := 1 to Pred(FileCount) do begin
    f := FileByIndex(i); 
    if GetElementNativeValues(ElementByIndex(f, 0), 'Record Header\Record Flags\ESL') = 0 then begin
      PrefixList.Add(IntToHex(espm, 2));
      Inc(espm);
    end
    else begin
      PrefixList.Add('FE' + IntToHex(esl, 3));
      Inc(esl);
    end;
  end;
end;

procedure BeginImport(BpPath: string; ToFile: IwbFile; WorkshopType: integer; DoScrapAll, SkipDups, skipLinks, PersistentRefs: boolean);
var
  BP, obj: TJsonObject;
  items: TJsonArray;
  PrefixedFormID_Dec, i, pi: integer;
  LayrEdid, PrefixedFormID_Hex: string;
  Layr, Quest, workshopRef, workshopRefDup, wscell, ref, baseObj: IInterface;
  ObjRefs, loaded_plugins: TStringList;
  f: IwbFile;
begin
  BP := TJsonObject.Create;
  loaded_plugins := TStringList.Create;
  ObjRefs := TStringList.Create;
  try
    // parse the blueprint in the path given by the argument BpPath (relative to Data)
    BP.LoadFromResource(BpPath);
    
    pi := GetPluginIndex(BP.O['workshop'].S['plugin']);
    
    if pi = -1 then begin
      Msg('***FATAL ERROR***', 'Settlement mod (' + BP.O['workshop'].S['plugin'] + ') not loaded, aborting.');
      exit;
    end;
    
    AddMessage('Importing ' + BP.O['header'].S['settlement_name'] + ' by ' + BP.O['header'].S['player_name'] + ' (' + BP.O['header'].S['item_count'] + ' items) to ' + GetFileName(ToFile) + ', please wait...');
    
    GetLoadedPlugins(BP.O['header'].A['plugins_required'], loaded_plugins);
    
    LayrEdid := ExtractFileName(BpPath);
    LayrEdid := OnlyAlpha(LayrEdid);
    Layr := AddMainRecord(ToFile, 'LAYR', LayrEdid);
		
    for i := 0 to Pred(loaded_plugins.Count) do
      AddMasterIfMissing(ToFile, loaded_plugins[i]);
        
    workshopRef := GetRef(pi, BP.O['workshop'].S['id']);
    
    if not Assigned(workshopRef) and not skipLinks then begin
      Msg('Error', 'The workshop reference does not exist in the loaded settlement esp.');
      exit;
    end;
    
    if Assigned(workshopRef) then begin
      // WorkshopRefDup stores the reference of the workshop, depending on the selected option.
      // Uses an override record or the original record.
      // Which will be used to store the Power Grid if powered workshop is selected.
      WorkshopRefDup := GetWorkshopRefDup(workshopRef, WorkshopType, ToFile);
      if DoScrapAll then ScrapAll(GetLoadOrderFormID(workshopRef), ToFile);
    end;
    
    pi := GetPluginIndex(BP.O['header'].S['cell_plugin']);
    
    if pi = -1 then begin
      Msg('***FATAL ERROR***', 'Settlement mod (' + BP.O['header'].S['cell_plugin'] + ') not loaded, aborting.');
      exit;
    end;
     
    // Get the cell in which the workshop is located
    wscell := GetRef(pi, BP.O['header'].S['cell_id']);
    
    if not Assigned(wscell) then begin
      Msg('Error', 'The workshop CELL does not exist in the loaded data.');
      exit;
    end;
    
    // Get the cell's persistent group
    wscell := ElementByIndex(ChildGroup(wscell), 0);
    
    wscell := GetExistingOrNewOverride(wscell, ToFile);
    
    // Array of items in the blueprint.
    items := BP.A['items'];
    
    // Import Objects Phase Loop
    for i := 0 to Pred(items.Count) do begin
      obj := items.O[i];
      
      // ObjRefs will be used in the power loop (right after this one),
      // It adds a blank index beforehand, so that the index of the object
      // and the index of the reference stored in this list will match.
      ObjRefs.Add('');
      
      // Skip if plugin is not loaded
      if not loaded_plugins.IndexOf(obj.S['plugin_name']) > -1 then continue;
      
      pi := GetPluginIndex(obj.S['plugin_name']);
      f := FileByIndex(pi);
      PrefixedFormID_Hex := GetLoadOrderPrefix(f) + obj.S['FormID'];
      PrefixedFormID_Dec := StrToInt('$' + PrefixedFormID_Hex);
      try
        baseObj := RecordByFormID(f, PrefixedFormID_Dec, true);
        
        if not Assigned(baseObj) then begin
          AddMessage('***ERROR***: Missing object with FormID: ' + PrefixedFormID_Hex + ' (' + obj.S['name'] + ' [' + obj.S['plugin_name'] + '])');
          continue;
        end;
        
        baseObj := MasterOrSelf(baseObj);
        
        if SkipDups then begin
          if (Signature(baseObj) <> 'NPC_') and not IsPickableObject(baseObj) and not HasCOBJ(baseObj) and (IsUnscrappableObject(baseObj) or not HasScrapCOBJ(baseObj)) then begin
            AddMessage('***Can not be stored in workshop nor scrapped***: Skipped object with FormID: ' + PrefixedFormID_Hex + ' (' + obj.S['name'] + ' [' + obj.S['plugin_name'] + '])');
            continue;
          end;
        end;
        
        ref := CreateNewRef(baseObj, obj, workshopRefDup, wscell, skipLinks);
        SetElementEditValues(ref, 'XLYR', Name(Layr));
        
        // Stores the FormID of the created object reference.
        ObjRefs.Insert(i, HexFormID(ref));
      except
        on E: Exception do
          AddMessage(E.Message);
        end
    end;
     
    if Assigned(WorkshopRefDup) then begin
      //if WorkshopType = 0 then //The quest is used for other ends than powering so it's used in all types.
      Quest := GeneratePoweringQuest(ToFile, OnlyAlpha(ExtractFileName(BpPath)), WorkshopRefDup);
    end;
    
    // Power and Persistance Loop
    for i := 0 to Pred(items.Count) do begin
      obj := items.O[i];
      
      // Skip if plugin is not loaded
      if not loaded_plugins.IndexOf(obj.S['plugin_name']) > -1 then continue;
      
      // Skip if ObjRefs[i] is empty
      if not IsHexFormID(ObjRefs[i]) then continue;
      
      ref := RecordByFormID(ToFile, StrToInt('$' + ObjRefs[i]), true);
            
      if not Assigned(ref) then continue;
      
      if (not PersistentRefs) and 
         (not HasKeyword(ref, 'WorkshopPowerConnection [KYWD:00054BA4]')) and 
         (not HasKeyword(ref, 'WorkshopCanBePowered [KYWD:0003037E]')) then begin
        SetIsPersistent(ref, false);
      end;
      
      // Do not proceed if 'Not Powered' is selected.
      if WorkshopType = 2 or not Assigned(WorkshopRefDup) then continue;
      
      // connect cables
      if not SameText(obj.S['ConnectedObjects'], '') then begin
        ConnectCables(items, i, ObjRefs, workshopRefDup, wscell, ToFile, Quest, WorkshopType);
      end;
      
      // if assigned radiator
      if obj.I['isPowered'] = 1 then begin
        if WorkshopType = 0 then
          AddConnectionToQuest(Quest, 0, ref, nil)
        else
          AddToPowerGrid(workshopRefDup, ref, workshopRefDup, nil);
      end;
      
      // Give power to snapped connections
      if HasActorValue(ref, 'WorkshopSnapTransmitsPower [AVIF:00000354]') then begin
        if WorkshopType = 0 then
          AddConnectionToQuest(Quest, 0, ref, nil)
        else
          AddToPowerGrid(workshopRefDup, ref, workshopRefDup, nil);
      end;
    // End 2nd Pass
    end;
  finally
    BP.Free;
    loaded_plugins.Free;
    ObjRefs.Free;
  end;
end;

procedure Msg(title, msg: string);
var
  frm: TForm;
  lbl: TLabel;
  btnOk: TButton;
begin
  frm := TForm.Create(nil);
  if FileExists(ScriptsPath + 'ts.ico') then
    frm.Icon.LoadFromFile(ScriptsPath + 'ts.ico');
  btnOk := TButton.Create(frm);
  try
    frm.Caption := title;
    frm.Position := poScreenCenter;
    lbl := ConstructLabel(frm, frm, 15, 15, 0, 0, msg);
    frm.Width := lbl.Width + 50;
    btnOk.Parent := frm;
    btnOk.Caption := 'OK';
    btnOk.ModalResult := mrOk;
    btnOk.Left := frm.Width div 2 - btnOk.Width div 2 - 10;
    btnOk.Top := lbl.Top + lbl.Height + 15;
    frm.Height := btnOk.Top + 80;
    frm.ShowModal;
  finally
    frm.Free;
  end;
end;

function Initialize: integer;
var
  frm: TForm;
  WorkshopTypes, Esps, Blueprints: TStringList;
  formSelectWorkshopType, formSelectEsp, formSelectBlueprint: TComboBox;
  formCheckPersistentRefs, formCheckSkipLinks, formCheckDoScrapAll, formCheckSkipDups: TCheckBox;
  SettingsFile, BpPath: string;
  ToFile: IwbFile;
  Settings : TJsonObject;
begin
  TopHeight := -20;
  SettingsFile := ScriptsPath + 'ImportBlueprint.json';
  
  WorkshopTypes := TStringList.Create;
  Esps := TStringList.Create;
  Blueprints := TStringList.Create;
  
  frm := TForm.Create(nil);
  
  formSelectWorkshopType := TComboBox.Create(frm);
  formSelectEsp := TComboBox.Create(frm);
  formSelectBlueprint := TComboBox.Create(frm);
  
  formCheckPersistentRefs := TCheckBox.Create(frm);
  formCheckSkipLinks := TCheckBox.Create(frm);
  formCheckDoScrapAll := TCheckBox.Create(frm);
  formCheckSkipDups := TCheckBox.Create(frm);
  
  Settings := TJsonObject.Create;
  
  try
    GenerateBlueprintList(Blueprints);
    
    if (Blueprints.Count = 0) then begin
      Msg('Error', 'There are no blueprints in the game folder.');
      exit;
    end;
    
    GenerateEspList(Esps);
    GenerateWorkshopTypeList(WorkshopTypes);
    
    if FileExists(ScriptsPath + 'ts.ico') then
      frm.Icon.LoadFromFile(ScriptsPath + 'ts.ico');
      
    frm.Caption := 'Import Blueprint to esp';
    frm.Width := 550;
    frm.Position := poScreenCenter;
    
    Settings.I['BlueprintIndex'] := 0;
    Settings.I['EspIndex'] := 0;
    Settings.I['WorkshopTypeIndex'] := 0;
    Settings.B['DoScrapAll'] := true;
    Settings.B['SkipDups'] := true;
    Settings.B['SkipLinks'] := false;
    Settings.B['PersistentRefs'] := false;
    
    if FileExists(SettingsFile) then Settings.LoadFromFile(SettingsFile);
    
    CreateSelector(formSelectBlueprint, frm, 'Blueprint', Blueprints, Settings.I['BlueprintIndex']);
    
    CreateSelector(formSelectEsp, frm, 'esp', Esps, Settings.I['EspIndex']);
    
    CreateSelector(formSelectWorkshopType, frm, 'Workshop Type', WorkshopTypes, Settings.I['WorkshopTypeIndex']);
    
    CreateCheckBox(formCheckDoScrapAll, frm, Settings.B['DoScrapAll'], 'Scrap All', 'Check this option if you want to scrap all objects using the list.');
    
    CreateCheckBox(formCheckSkipDups,frm, Settings.B['SkipDups'], 'Skip Possible Dups', 'Check this option if you want to skip importing objects that can not be either scrapped nor stored.' + #13#10 +
                                                                  'If you allow importing objects that are unscrappable and unstorable,' + #13#10 +
                                                                  'they will turn in to duplicated objects, in this settlement,' + #13#10 +
                                                                  'or in a blueprint generated from the resulting settlement.');
    
    CreateCheckBox(formCheckSkipLinks, frm, Settings.B['SkipLinks'], 'Skip Links', 'Check this option if you want to skip linking objects to the workshop.' + #13#10 +
                                                                     'DO NOT CHECK unless you are not using the imported objects as a settlement.');
    
    CreateCheckBox(formCheckPersistentRefs, frm, Settings.B['PersistentRefs'], 'Persistent References', 'Check this option if you want all references to be persistent.');
    
    TopHeight := TopHeight + 15;
    ConstructOkCancelButtons(frm, frm, TopHeight);
    
    frm.Height := TopHeight + 80;
    
    if frm.ShowModal = mrOk then begin
      Settings.I['BlueprintIndex'] := formSelectBlueprint.ItemIndex;
      Settings.I['EspIndex'] := formSelectEsp.ItemIndex;
      Settings.I['WorkshopTypeIndex'] := formSelectWorkshopType.ItemIndex;
      Settings.B['DoScrapAll'] := formCheckDoScrapAll.Checked;
      Settings.B['SkipDups'] := formCheckSkipDups.Checked;
      Settings.B['SkipLinks'] := formCheckSkipLinks.Checked;
      Settings.B['PersistentRefs'] := formCheckPersistentRefs.Checked;
      Settings.SaveToFile(SettingsFile);
      
      BpPath := 'F4SE\Plugins\TransferSettlements\blueprints\' + formSelectBlueprint.Text;
      if not ResourceExists(BpPath) then begin
        Msg('Error', 'File "' + BpPath + '" could not be found in the Data folder.');
        exit;
      end;
      
      if formSelectEsp.Text = '<New File>' then begin
        ToFile := AddNewFile; //Shows a dialog to create a new esp.
      end
      else begin
        if formSelectEsp.Text <> '' then begin
          ToFile := FileByIndex(GetPluginIndex(formSelectEsp.Text));
        end;
      end;
      
      if not Assigned(ToFile) then begin
        Msg('Error', 'Invalid File Name.');
        exit;
      end;
      
      InitializePrefixList;
      
      BeginImport(BpPath, ToFile, formSelectWorkshopType.ItemIndex, formCheckDoScrapAll.Checked, formCheckSkipDups.Checked, formCheckSkipLinks.Checked, formCheckPersistentRefs.Checked);
    end
    else begin
      AddMessage('Import canceled.');
      exit;
    end;
    
  finally
    Settings.Free;
    WorkshopTypes.Free;
    Esps.Free;
    Blueprints.Free;
    
    formSelectWorkshopType.Free;
    formSelectEsp.Free;
    formSelectBlueprint.Free;
    
    formCheckPersistentRefs.Free;
    formCheckSkipLinks.Free;
    formCheckDoScrapAll.Free;
    formCheckSkipDups.Free;
    
    frm.Free;
  end;
end;

end.