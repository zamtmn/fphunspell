unit hunspell;
{$Mode delphi}{$H+}
{$ModeSwitch advancedrecords}

interface

uses
  Classes,dynlibs,SysUtils,LazFileUtils;

resourcestring
  rsDictionaryFileNotFound='Dictionary file "%s" not found';
  rsFailedToLoadLibrary='Failed to load library %s';
  rsLibraryLoaded='Library "%s" loaded';
  rsWrongLibrary='Failed to find Hunspell_ functions in "%s"';

{$INCLUDE hunspell.inc}

type
  TMsgType=(MsgInfo,MsgCriticalInfo,MsgWarning,MsgError);
  TMsg=string;
  TLogProc=procedure(MsgType:TMsgType;Msg:TMsg);

  PHunspell=^THunspell;
  THunspell=record
    private
      pHunspell:Pointer;
      LogProc:TLogProc;
      function LoadHunspellLib(ALibName:String):Boolean;
      procedure FreeHunspellLib;
      procedure LWarning(AMsg:string);
      procedure LError(AMsg:string);
      procedure LInfo(AMsg:string);
    public
      constructor CreateRec(const ALibName:String;ALogProc:TLogProc);
      procedure DestroyRec;
      function isReady:boolean;
      function Spell(Word: string): boolean;//true if ok
      procedure Suggest(Word: string; List: TStrings);
      procedure Add(Word: string);
      procedure Remove(Word: string);
      function SetDictionary(const DictName: string) : boolean;
  end;

implementation

var
  HunLibHandle:TLibHandle;
  Hunspell_create: THunspell_create;
  Hunspell_destroy: THunspell_destroy;
  Hunspell_spell: Thunspell_spell;
  Hunspell_suggest: Thunspell_suggest;
  Hunspell_analyze: Thunspell_analyze;
  Hunspell_stem: Thunspell_stem;
  Hunspell_get_dic_encoding: Thunspell_get_dic_encoding;
  Hunspell_add: THunspell_add;
  Hunspell_free_list: THunspell_free_list;
  Hunspell_remove: THunspell_remove;

procedure THunspell.LWarning(AMsg:string);
begin
  if @LogProc<>nil then
    LogProc(MsgWarning,AMsg);
end;

procedure THunspell.LError(AMsg:string);
begin
  if @LogProc<>nil then
    LogProc(MsgError,AMsg);
end;

procedure THunspell.LInfo(AMsg:string);
begin
  if @LogProc<>nil then
    LogProc(MsgInfo,AMsg);
end;

procedure THunspell.FreeHunspellLib;
begin
  FreeLibrary(HunLibHandle);
  HunLibHandle:=NilHandle;
end;

function THunspell.LoadHunspellLib(ALibName:String):Boolean;
begin
    HunLibHandle := LoadLibrary(PAnsiChar(ALibName));
    if HunLibHandle = NilHandle then begin
        LError(format(rsFailedToLoadLibrary,[ALibName]));
        exit(false);
    end else begin
        Result := True;
        Hunspell_create := THunspell_create(GetProcAddress(HunLibHandle, 'Hunspell_create'));
        if not Assigned(Hunspell_create) then Result := False; 
    	Hunspell_destroy := Thunspell_destroy(GetProcAddress(HunLibHandle, 'Hunspell_destroy'));
        if not Assigned(Hunspell_destroy) then Result := False;
        Hunspell_spell := THunspell_spell(GetProcAddress(HunLibHandle, 'Hunspell_spell'));
        if not Assigned(Hunspell_spell) then Result := False;
        Hunspell_suggest := THunspell_suggest(GetProcAddress(HunLibHandle, 'Hunspell_suggest'));
        if not Assigned(Hunspell_suggest) then Result := False;
        Hunspell_analyze := THunspell_analyze(GetProcAddress(HunLibHandle, 'Hunspell_analyze'));
        if not Assigned(Hunspell_analyze) then Result := False;
        Hunspell_stem := THunspell_stem(GetProcAddress(HunLibHandle, 'Hunspell_stem'));
        if not Assigned(Hunspell_stem) then Result := False;
        Hunspell_get_dic_encoding := THunspell_get_dic_encoding(GetProcAddress(HunLibHandle, 'Hunspell_get_dic_encoding'));
        if not Assigned(Hunspell_get_dic_encoding) then Result := False;
        Hunspell_free_list := THunspell_free_list(GetProcAddress(HunLibHandle, 'Hunspell_free_list'));
        if not Assigned(Hunspell_free_list) then Result := False;
        Hunspell_add := THunspell_add(GetProcAddress(HunLibHandle, 'Hunspell_add'));
        if not Assigned(Hunspell_add) then Result := False;
        Hunspell_remove := THunspell_remove(GetProcAddress(HunLibHandle, 'Hunspell_remove'));
        if not Assigned(Hunspell_remove) then Result := False;
    end;
    if Result then
      LInfo(format(rsLibraryLoaded,[ALibName]))
    else
      LError(format(rsWrongLibrary,[ALibName]));
end;

constructor THunspell.CreateRec(const ALibName:String;ALogProc:TLogProc);
var
  VLibName:string;
begin
  pHunspell:=nil;
  LogProc:=ALogProc;
  if ALibName<>''then
    VLibName:=ALibName
  else
    {$IFDEF LINUX}
    VLibName:='hunspell.so';
    {$ENDIF}
    {$ifdef DARWIN}
    VLibName:='libhunspell.so';
    {$endif}
    {$ifdef WINDOWS}
    VLibName:='libhunspell.dll';
    {$endif}
  LoadHunspellLib(VLibName);
end;

procedure THunspell.DestroyRec;
begin
  if pHunspell<>nil then begin
    hunspell_destroy(pHunspell);
    pHunspell:=nil;
  end;
  if HunLibHandle<>0 then
    FreeHunspellLib;
end;

function THunspell.isReady:boolean;
begin
  result:=pHunspell<>nil;
end;

function THunspell.Spell(Word:string):boolean;
begin
  if isReady then
    Result := hunspell_spell(pHunspell,PChar(Word))
  else
    result:=true;
end;

procedure THunspell.Suggest(Word:string;List:TStrings);
var
  i,len:Integer;
  SugList,Words:PPChar;
begin
  if isReady then begin
    List.clear;
    try
      len := hunspell_suggest(pHunspell,SugList,PChar(Word));
      Words := SugList;
      for i := 1 to len do begin
        List.Add(Words^);
        Inc(PtrInt(Words),sizeOf(Pointer));
      end;
    finally
      Hunspell_free_list(pHunspell,SugList, len);
    end;
  end;
end;

procedure THunspell.Add(Word:string);
begin
  if isReady then
    Hunspell_add(pHunspell,Pchar(Word));
end;

procedure THunspell.Remove(Word:string);
begin
  if isReady then
    Hunspell_remove(pHunspell,Pchar(Word));
end;

function THunspell.SetDictionary(const DictName:string):boolean;
var
  Aff:string;
begin
  if HunLibHandle<>NilHandle then begin
    LInfo(format('THunspell.SetDictionary(%s)',[DictName]));
    if not FileExists(DictName) then begin
      LInfo(format(rsDictionaryFileNotFound,[DictName]));
      exit(False);
    end;
    Aff:=ExtractFileNameWithoutExt(DictName);
    Aff:=Aff+'.aff';
    if not FileExists(Aff) then begin
      LInfo(format(rsDictionaryFileNotFound,[DictName]));
      exit(False);
    end;
    try
      if assigned(pHunspell) then
        hunspell_destroy(pHunspell)
      else
        pHunspell:=hunspell_create(PChar(Aff),PChar(DictName));
    except
      on E: Exception do LError(format('Hunspell %s',[E.Message]));
      else
        LError('Expection in THunspell.SetDictionary');
    end;
    Result:=pHunspell<>nil;
  end;
end;

initialization
  HunLibHandle:=NilHandle;
end.
