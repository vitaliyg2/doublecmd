unit uAdministrator;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

function FileOpenUAC(const FileName: String; Mode: LongWord): System.THandle;
function FileCreateUAC(const FileName: String; Mode: LongWord): System.THandle;

function DeleteFileUAC(const FileName: String): LongBool;
function RenameFileUAC(const OldName, NewName: String): LongBool;

function CreateDirectoryUAC(const Directory: String): Boolean;
function RemoveDirectoryUAC(const Directory: String): Boolean;

function CreateSymbolicLinkUAC(const Path, LinkName: String) : Boolean;
function CreateHardLinkUAC(const Path, LinkName: String) : Boolean;

type

  { TFileStreamUAC class }

  TFileStreamUAC = class(THandleStream)
  private
    FHandle: THandle;
    FFileName: String;
  protected
    procedure SetSize64(const NewSize: Int64); override;
  public
    constructor Create(const AFileName: String; Mode: LongWord);
    destructor Destroy; override;
    function Flush: Boolean;
    function Read(var Buffer; Count: LongInt): LongInt; override;
    property FileName: String read FFileName;
  end;

threadvar
  ElevateAction: Boolean;

implementation

uses
  RtlConsts, DCOSUtils, LCLType, uShowMsg, uElevation, uSuperUser, fElevation;

resourcestring
  rsElevationRequired = 'You need to provide administrator permission';
  rsElevationRequiredDelete = 'to delete this object:';
  rsElevationRequiredOpen = 'to open this object:';
  rsElevationRequiredCreate = 'to create this object:';
  rsElevationRequiredRename = 'to rename this object:';
  rsElevationRequiredHardLink = 'to create this hard link:';
  rsElevationRequiredSymLink = 'to create this symbolic link:';

function RequestElevation(const Message, FileName: String): Boolean;
var
  Text: String;
begin
  if ElevateAction then Exit(True);
  Text:= rsElevationRequired + LineEnding;
  Text += Message + LineEnding + FileName;
  case ShowElevation(mbSysErrorMessage, Text) of
    mmrOK: Result:= True;
    mmrCancel: Result:= False;
    mmrAll: begin
      Result:= True;
      ElevateAction:= True;
    end;
  end;
end;

function FileOpenUAC(const FileName: String; Mode: LongWord): System.THandle;
var
  LastError: Integer;
begin
  Result:= mbFileOpen(FileName, Mode);
  if (Result = feInvalidHandle) and ElevationRequired then
  begin
    LastError:= GetLastOSError;
    if RequestElevation(rsElevationRequiredOpen, FileName) then
      Result:= TWorkerProxy.Instance.FileOpen(FileName, Mode)
    else
      SetLastOSError(LastError);
  end;
end;

function FileCreateUAC(const FileName: String; Mode: LongWord): System.THandle;
var
  LastError: Integer;
begin
  Result:= mbFileCreate(FileName, Mode);
  if (Result = feInvalidHandle) and ElevationRequired then
  begin
    LastError:= GetLastOSError;
    if RequestElevation(rsElevationRequiredCreate, FileName) then
      Result:= TWorkerProxy.Instance.FileCreate(FileName, Mode)
    else
      SetLastOSError(LastError);
  end;
end;

function DeleteFileUAC(const FileName: String): LongBool;
var
  LastError: Integer;
begin
  Result:= mbDeleteFile(FileName);
  if (not Result) and ElevationRequired then
  begin
    LastError:= GetLastOSError;
    if RequestElevation(rsElevationRequiredDelete, FileName) then
      Result:= TWorkerProxy.Instance.DeleteFile(FileName)
    else
      SetLastOSError(LastError);
  end;
end;

function RenameFileUAC(const OldName, NewName: String): LongBool;
var
  LastError: Integer;
begin
  Result:= mbRenameFile(OldName, NewName);
  if (not Result) and ElevationRequired then
  begin
    LastError:= GetLastOSError;
    if RequestElevation(rsElevationRequiredRename, OldName) then
      Result:= TWorkerProxy.Instance.RenameFile(OldName, NewName)
    else
      SetLastOSError(LastError);
  end;
end;

function CreateDirectoryUAC(const Directory: String): Boolean;
var
  LastError: Integer;
begin
  Result:= mbCreateDir(Directory);
  if (not Result) and ElevationRequired then
  begin
    LastError:= GetLastOSError;
    if RequestElevation(rsElevationRequiredCreate, Directory) then
      Result:= TWorkerProxy.Instance.CreateDirectory(Directory)
    else
      SetLastOSError(LastError);
  end;
end;

function RemoveDirectoryUAC(const Directory: String): Boolean;
var
  LastError: Integer;
begin
  Result:= mbRemoveDir(Directory);
  if (not Result) and ElevationRequired then
  begin
    LastError:= GetLastOSError;
    if RequestElevation(rsElevationRequiredDelete, Directory) then
      Result:= TWorkerProxy.Instance.RemoveDirectory(Directory)
    else
      SetLastOSError(LastError);
  end;
end;

function CreateHardLinkUAC(const Path, LinkName: String): Boolean;
var
  LastError: Integer;
begin
  Result:= CreateHardLink(Path, LinkName);
  if (not Result) and ElevationRequired then
  begin
    LastError:= GetLastOSError;
    if RequestElevation(rsElevationRequiredHardLink, LinkName) then
      Result:= TWorkerProxy.Instance.CreateHardLink(Path, LinkName)
    else
      SetLastOSError(LastError);
  end;
end;

function CreateSymbolicLinkUAC(const Path, LinkName: String): Boolean;
var
  LastError: Integer;
begin
  Result:= CreateSymLink(Path, LinkName);
  if (not Result) and ElevationRequired then
  begin
    LastError:= GetLastOSError;
    if RequestElevation(rsElevationRequiredSymLink, LinkName) then
      Result:= TWorkerProxy.Instance.CreateSymbolicLink(Path, LinkName)
    else
      SetLastOSError(LastError);
  end;
end;

{ TFileStreamUAC }

procedure TFileStreamUAC.SetSize64(const NewSize: Int64);
begin
  FileAllocate(FHandle, NewSize);
end;

constructor TFileStreamUAC.Create(const AFileName: String; Mode: LongWord);
begin
  if (Mode and fmCreate) <> 0 then
    begin
      FHandle:= FileCreateUAC(AFileName, Mode);
      if FHandle = feInvalidHandle then
        raise EFCreateError.CreateFmt(SFCreateError, [AFileName])
      else
        inherited Create(FHandle);
    end
  else
    begin
      FHandle:= FileOpenUAC(AFileName, Mode);
      if FHandle = feInvalidHandle then
        raise EFOpenError.CreateFmt(SFOpenError, [AFilename])
      else
        inherited Create(FHandle);
    end;
  FFileName:= AFileName;
end;

destructor TFileStreamUAC.Destroy;
begin
  inherited Destroy;
  // Close handle after destroying the base object, because it may use Handle in Destroy.
  if FHandle <> feInvalidHandle then FileClose(FHandle);
end;

function TFileStreamUAC.Flush: Boolean;
begin
  Result:= FileFlush(FHandle);
end;

function TFileStreamUAC.Read(var Buffer; Count: LongInt): LongInt;
begin
  Result:= FileRead(FHandle, Buffer, Count);
  if Result = -1 then
    raise EReadError.Create(mbSysErrorMessage(GetLastOSError));
end;

var
  ChildProcess: UIntPtr = 0;

function WaitProcessThread(Parameter : Pointer): PtrInt;
begin
  Result:= 0;
  WaitProcess(ChildProcess);
  ChildProcess:= 0;
  EndThread(Result);
end;

procedure ElevateProcedure;
begin
  ChildProcess:= ExecCmdAdmin(ParamStr(0), ['--service', IntToStr(GetProcessID)]);
  if ChildProcess > 0 then
  begin
    {$PUSH}{$WARNINGS OFF}{$HINTS OFF}
    BeginThread(@WaitProcessThread);
    {$POP}
  end;
end;

procedure Initialize;
begin
  ElevateSelf:= @ElevateProcedure;
end;

initialization
  Initialize;

finalization
  if ChildProcess > 0 then TerminateProcess(ChildProcess);

end.

