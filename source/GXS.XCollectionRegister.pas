//
// The graphics engine GXScene https://github.com/glscene
//
unit GXS.XCollectionRegister;

(* Register TXCollection property editor *)
(* TODO *)

interface

{$I GXS.Scene.inc}

uses
  System.Classes,
  System.TypInfo,

///  DesignEditors,
///  DesignIntf,

    GXS.XCollection,
    FxXCollectionEditor;

type
	TXCollectionProperty = class(TClassProperty)
	public
      	  function GetAttributes: TPropertyAttributes; override;
	  procedure Edit; override;
	end;

procedure Register;

// ------------------------------------------------------------------
implementation
// ------------------------------------------------------------------

//----------------- TXCollectionProperty ------------------------------------

function TXCollectionProperty.GetAttributes: TPropertyAttributes;
begin
	Result:=[paDialog];
end;

procedure TXCollectionProperty.Edit;
begin
   with FXCollectionEditor do begin
     SetXCollection(TXCollection(GetOrdValue), Self.Designer);
     Show;
   end;
end;

procedure Register;
begin
  RegisterPropertyEditor(TypeInfo(TXCollection), nil, '', TXCollectionProperty);
end;


// ------------------------------------------------------------------
initialization
// ------------------------------------------------------------------



end.
