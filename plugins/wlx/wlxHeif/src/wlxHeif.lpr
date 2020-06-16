library wlxHeif;

{$include calling.inc}

uses
  Classes,
  sysutils,
  Interfaces, LCLType, Controls, StdCtrls, ExtCtrls,
  Forms,
  Graphics,
  FPImage,
  WlxPlugin, HEIF;
  
 var List:TStringList;

 //Custom class contains info for plugin windows
 type

 { TPlugInfo }

 TPlugInfo = class
        private
         fControls:TStringList;
        public
        fFileToLoad:string;
        fShowFlags:integer;
        //etc
        constructor Create;
        destructor Destroy; override;
        function AddControl(AItem:TPanel):integer;
      end;

 { TPlugInfo }

 constructor TPlugInfo.Create;
 begin
  fControls:=TStringlist.Create;
 end;

destructor TPlugInfo.Destroy;
begin
  while fControls.Count>0 do
  begin
    fControls.Objects[0].Free;
    fControls.Delete(0);
  end;
  inherited Destroy;
end;

function TPlugInfo.AddControl(AItem: TPanel): integer;
begin
  Result := fControls.AddObject(inttostr(IntPtr(AItem)),TObject(AItem));
end;


function DecodeFile(const AFileName: string; ABitmap: TBitmap; out AErrorMessage: string): Boolean;
 var
   Context: Pheif_context;
   PrimaryImage: Pheif_image_handle;
   DecodedImage: Pheif_image;
   W, H, X, Y: Integer;
   ImageData: Puint8_t;
   Stride: Integer;
   ScanLine: PByte;
   Error: heif_error;
 begin
   Result := False;

   Context := heif_context_alloc;
   try
     Error := heif_context_read_from_file(Context, PAnsiChar(AnsiString(AFileName)), nil);
     if Error.code <> heif_error_Ok then
       begin
         AErrorMessage:= Error.message;
         Exit;
       end;

     Error := heif_context_get_primary_image_handle(Context, PrimaryImage);
     if Error.code <> heif_error_Ok then
       begin
         AErrorMessage:= Error.message;
         Exit;
       end;

     try
       Error := heif_decode_image(PrimaryImage, DecodedImage, heif_colorspace_RGB,
         heif_chroma_interleaved_RGB, nil);
       if Error.code <> heif_error_Ok then
         begin
           AErrorMessage:= Error.message;
           Exit;
         end;

       try
         W := heif_image_get_width(DecodedImage, heif_channel_interleaved);
         H := heif_image_get_height(DecodedImage, heif_channel_interleaved);

         Stride := 0;
         ImageData := heif_image_get_plane_readonly(DecodedImage,
           heif_channel_interleaved, Stride);
         ABitmap.SetSize(W, H);
         ABitmap.PixelFormat:= pf24bit;
         ABitmap.Canvas.Lock;
         try
           for Y := 0 to H - 1 do
           begin
             ScanLine := ABitmap.ScanLine[y];
             for X := 0 to W - 1 do
             begin
               ScanLine[2 + 3*X] := ImageData[0 + 3 * X + Y * Stride];
               ScanLine[1 + 3*X] := ImageData[1 + 3 * X + Y * Stride];
               ScanLine[0 + 3*X] := ImageData[2 + 3 * X + Y * Stride];
               //ABitmap.Canvas.Pixels[X, Y] :=
               //  RGBToColor(
               //  ImageData[0 + 3 * X + Y * Stride],
               //  ImageData[1 + 3 * X + Y * Stride],
               //  ImageData[2 + 3 * X + Y * Stride]
               //);

  //               ImageData[3 + SizeOf(TAlphaColor) * X + Y * Stride];

               //ABitmap.Canvas.Colors [X, Y] := FPColor(
               //    ImageData[0 + 3 * X + Y * Stride]*255,
               //    ImageData[1 + 3 * X + Y * Stride]*255,
               //    ImageData[2 + 3 * X + Y * Stride]*255
               //    );
  //             Pixels[X, Y] := C;
             end;
           end;

         finally
           ABitmap.Canvas.Unlock;
         end;

 //        Move(p^, Bitmap.Bits^, w*h*SizeOf(TAlphaColor));
       finally
         heif_image_release(DecodedImage);
       end;
     finally
       heif_image_handle_release(PrimaryImage);
     end;
   finally
     heif_context_free(Context);
   end;
   Result := True;
end;

function ListLoad(ParentWin:thandle;FileToLoad:PAnsiChar;ShowFlags:integer):thandle; dcpcall;
var
  MainPanel: TPanel;
  Image: TImage;
  b: TBitmap;
  lblError: TLabel;
  ErrorMessage: string;
begin
  MainPanel:= TPanel.create(nil);
  MainPanel.ParentWindow:=ParentWin;
  MainPanel.ParentBackground:= False;
  MainPanel.Color := clWhite;

  lblError := TLabel.Create(MainPanel);
  lblError.Parent := MainPanel;
  lblError.AutoSize:= False;
  lblError.Align:= alClient;
  lblError.Font.Size:= 13;
  lblError.Font.Color:=clRed;
  lblError.Visible:=False;
  lblError.Alignment:= TAlignment.taCenter;
  lblError.Layout:=TTextLayout.tlCenter;
  lblError.WordWrap:=True;

  Image := TImage.Create(MainPanel);
  Image.Parent := MainPanel;
  Image.Align:= alClient;
  Image.Stretch:= True;
  Image.Proportional:= True;
  Image.Center:=True;

  //Create list if none
  if not assigned(List) then
    List:=TStringList.Create;

  //add to list new plugin window and it's info
  List.AddObject(IntToStr(IntPtr(MainPanel.Handle)),TPlugInfo.Create);
  with TPlugInfo(List.Objects[List.Count-1]) do
  begin
    fFileToLoad:=FileToLoad;
    fShowFlags:=ShowFlags;
    AddControl(MainPanel);
  end;

  Result:= thandle(MainPanel.Handle);

  b := TBitmap.Create;
  try
    if not DecodeFile(FileToLoad, b, ErrorMessage) then
    begin
      Image.Visible := False;
      lblError.Visible:=True;
      lblError.Caption:=ErrorMessage;
      Exit;
    end;
    Image.Picture.Assign(B);
  finally
    FreeAndNil(b);
  end;
end;

procedure ListCloseWindow(ListWin:thandle); dcpcall;
 var Index:integer; s:string;
begin
 if assigned(List) then
   begin
     s:=IntToStr(ListWin);
     Index:=List.IndexOf(s);
     if Index>-1 then
       begin
         TPlugInfo(List.Objects[index]).Free;
         List.Delete(Index);
       end;

     //Free list if it has zero items
     If List.Count=0 then  FreeAndNil(List);
   end;

end;

procedure ListGetDetectString(DetectString:pchar;maxlen:integer); dcpcall;
begin
  StrLCopy(DetectString, '(EXT="HEIF")|(EXT="HEIC")|(EXT="AVIF")', maxlen);
end;

exports
       ListLoad,
       ListCloseWindow,
       ListGetDetectString;

{$R *.res}

begin
  Application.Initialize;
end.

