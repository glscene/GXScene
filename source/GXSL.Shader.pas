//
// The graphics engine GXScene https://github.com/glscene
//
unit GXSL.Shader;

(* GLXLShader is a wrapper for all GLX shaders *)

interface

{$I GXS.Scene.inc}

uses
  Winapi.OpenGL,
  Winapi.OpenGLext,
  System.Classes,
  System.SysUtils,

  GXS.VectorGeometry,
  GXS.VectorTypes,
  GXS.Texture,
  GXS.Context,
  GXS.RenderContextInfo,
  GXS.TextureFormat,

  GXSL.CustomShader,
  GXSL.Parameter;

type
  TgxslShaderParameter = class;
  TgxslCustomShader = class;
  EgxslShaderException = class(ECustomShaderException);

  TgxslShaderEvent = procedure(Shader: TgxslCustomShader) of object;
  TgxslShaderUnApplyEvent = procedure(Shader: TgxslCustomShader;
                                     var ThereAreMorePasses: Boolean) of object;
  TgxslShaderEventEx = procedure(Shader: TgxslCustomShader;
    Sender: TObject) of object;

  TgxActiveAttrib = record
    Name: string;
    Size: Integer;
    AType: TgxSLDataType;
    Location: Integer;
  end;

  TgxActiveAttribArray = array of TgxActiveAttrib;

  TgxslCustomShader = class(TgxCustomShader)
  private
    FGXSLProg: TgxProgramHandle;
    FParam: TgxslShaderParameter;
    FActiveVarying: TStrings;
    FTransformFeedBackMode: TgxTransformFeedBackMode;
    FOnInitialize: TgxslShaderEvent;
    FOnApply: TgxslShaderEvent;
    FOnUnApply: TgxslShaderUnApplyEvent;
    FOnInitializeEx: TgxslShaderEventEx;
    FOnApplyEx: TgxslShaderEventEx;
    function GetParam(const Index: string): TgxslShaderParameter;
    function GetDirectParam(const Index: Cardinal): TgxslShaderParameter;
    procedure OnChangeActiveVarying(Sender: TObject);
  protected
    property OnApply: TgxslShaderEvent read FOnApply write FOnApply;
    property OnUnApply: TgxslShaderUnApplyEvent read FOnUnApply write FOnUnApply;
    property OnInitialize: TgxslShaderEvent read FOnInitialize write FOnInitialize;
    property OnInitializeEx: TgxslShaderEventEx read FOnInitializeEx write FOnInitializeEx;
    property OnApplyEx: TgxslShaderEventEx read FOnApplyEx write FOnApplyEx;
    function GetGXSLProg: TgxProgramHandle; virtual;
    function GetCurrentParam: TgxslShaderParameter; virtual;
    procedure SetActiveVarying(const Value: TStrings);
    procedure SetTransformFeedBackMode(const Value: TgxTransformFeedBackMode);
    procedure DoInitialize(var rci: TgxRenderContextInfo; Sender: TObject); override;
    procedure DoFinalize; override;
    procedure DoApply(var rci: TgxRenderContextInfo; Sender: TObject); override;
    function DoUnApply(var rci: TgxRenderContextInfo): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    function ShaderSupported: Boolean; override;
    function GetActiveAttribs: TgxActiveAttribArray;
    property Param[const Index: string]: TgxslShaderParameter read GetParam;
    property DirectParam[const Index: Cardinal]: TgxslShaderParameter read GetDirectParam;
    property ActiveVarying: TStrings read FActiveVarying write SetActiveVarying;
    property TransformFeedBackMode: TgxTransformFeedBackMode read FTransformFeedBackMode write SetTransformFeedBackMode default tfbmInterleaved;
  end;

  // Wrapper around a parameter of a GLSL program.
  TgxslShaderParameter = class(TgxCustomShaderParameter)
  private
    FGXSLProg: TgxProgramHandle;
    FParameterID: Integer;
  protected
    function GetAsVector1f: Single; override;
    function GetAsVector2f: TVector2f; override;
    function GetAsVector3f: TVector3f; override;
    function GetAsVector4f: TVector4f; override;
    function GetAsVector1i: Integer; override;
    function GetAsVector2i: TVector2i; override;
    function GetAsVector3i: TVector3i; override;
    function GetAsVector4i: TVector4i; override;
    function GetAsVector1ui: Cardinal; override;
    function GetAsVector2ui: TVector2ui; override;
    function GetAsVector3ui: TVector3ui; override;
    function GetAsVector4ui: TVector4ui; override;
    procedure SetAsVector1f(const Value: Single); override;
    procedure SetAsVector2f(const Value: TVector2f); override;
    procedure SetAsVector3f(const Value: TVector3f); override;
    procedure SetAsVector4f(const Value: TVector4f); override;
    procedure SetAsVector1i(const Value: Integer); override;
    procedure SetAsVector2i(const Value: TVector2i); override;
    procedure SetAsVector3i(const Value: TVector3i); override;
    procedure SetAsVector4i(const Value: TVector4i); override;
    procedure SetAsVector1ui(const Value: Cardinal); override;
    procedure SetAsVector2ui(const Value: TVector2ui); override;
    procedure SetAsVector3ui(const Value: TVector3ui); override;
    procedure SetAsVector4ui(const Value: TVector4ui); override;
    function GetAsMatrix2f: TMatrix2f; override;
    function GetAsMatrix3f: TMatrix3f; override;
    function GetAsMatrix4f: TMatrix4f; override;
    procedure SetAsMatrix2f(const Value: TMatrix2f); override;
    procedure SetAsMatrix3f(const Value: TMatrix3f); override;
    procedure SetAsMatrix4f(const Value: TMatrix4f); override;
    function GetAsCustomTexture(const TextureIndex: Integer;
      TextureTarget: TgxTextureTarget): Cardinal; override;
    procedure SetAsCustomTexture(const TextureIndex: Integer;
      TextureTarget: TgxTextureTarget; const Value: Cardinal); override;
    function GetAsUniformBuffer: GLenum; override;
    procedure SetAsUniformBuffer( UBO: GLenum); override;
   public
     // Nothing here ...yet.
   end;

  TgxslShader = class(TgxslCustomShader)
  published
    property FragmentProgram;
    property VertexProgram;
    property GeometryProgram;
    property OnApply;
    property OnApplyEx;
    property OnUnApply;
    property OnInitialize;
    property OnInitializeEx;
    property ShaderStyle;
    property FailedInitAction;
    property ActiveVarying;
    property TransformFeedBackMode;
  end;


//=============================================================
implementation
//=============================================================

uses
  GXS.State;

//---------------------------------
// TgxslCustomShader
//---------------------------------

procedure TgxslCustomShader.DoApply(var rci: TgxRenderContextInfo; Sender: TObject);
begin
  FGXSLProg.UseProgramObject;
  if Assigned(FOnApply) then
    FOnApply(Self);
  if Assigned(FOnApplyEx) then
    FOnApplyEx(Self, Sender);
end;

procedure TgxslCustomShader.DoInitialize(var rci: TgxRenderContextInfo; Sender: TObject);
const
  cBufferMode: array[tfbmInterleaved..tfbmSeparate] of GLenum = (
    GL_INTERLEAVED_ATTRIBS_EXT, GL_SEPARATE_ATTRIBS_EXT);
var
  i, NumVarying: Integer;
  sVaryings: array of AnsiString;
  pVaryings: array of PGLChar;
begin
  try
    if not ShaderSupported then
      HandleFailedInitialization
    else
    try
      FGXSLProg.AllocateHandle;
      if FGXSLProg.IsDataNeedUpdate then
      begin
        if Name <> '' then
          FGXSLProg.Name := Name
        else
          FGXSLProg.Name := ClassName;

        FGXSLProg.DetachAllObject;
        if VertexProgram.Enabled then
          FGXSLProg.AddShader(TgxVertexShaderHandle, VertexProgram.Code.Text, FDebugMode);
        if FragmentProgram.Enabled then
          FGXSLProg.AddShader(TgxFragmentShaderHandle, FragmentProgram.Code.Text, FDebugMode);
        if GeometryProgram.Enabled then
          FGXSLProg.AddShader(TgxGeometryShaderHandle, GeometryProgram.Code.Text, FDebugMode);

        if VertexProgram.Enabled or FragmentProgram.Enabled or GeometryProgram.Enabled then
        begin
          if GeometryProgram.Enabled then
          begin
            glProgramParameteri(FGXSLProg.Handle, GL_GEOMETRY_INPUT_TYPE_EXT,
              cGXgsInTypes[GeometryProgram.InputPrimitiveType]);
            glProgramParameteri(FGXSLProg.Handle, GL_GEOMETRY_OUTPUT_TYPE_EXT,
              cGXgsOutTypes[GeometryProgram.OutputPrimitiveType]);
            glProgramParameteri(FGXSLProg.Handle, GL_GEOMETRY_VERTICES_OUT_EXT,
              GeometryProgram.VerticesOut);
          end;

          NumVarying := FActiveVarying.Count;
          if NumVarying > 0 then
          begin
            // Activate varying
            SetLength(sVaryings, NumVarying);
            SetLength(pVaryings, NumVarying);
            for i := 0 to NumVarying - 1 do
            begin
              sVaryings[i] := AnsiString(FActiveVarying.Strings[i]) + #0;
              pVaryings[i] := PAnsiChar( sVaryings[i] );
            end;
            glTransformFeedbackVaryings(
              FGXSLProg.Handle, NumVarying, @pVaryings[0],
              cBufferMode[FTransformFeedBackMode] );
          end;

          if (not FGXSLProg.LinkProgram) then
            raise EgxslShaderException.Create(FGXSLProg.InfoLog);
        end;
        FGXSLProg.NotifyDataUpdated;
      end;
    except
      on E: Exception do
      begin
        Enabled := False;
        HandleFailedInitialization(E.Message);
      end;
    end;

  finally
    if Enabled then
    try
      if Assigned(FOnInitialize) then
      begin
        FGXSLProg.UseProgramObject;
        FOnInitialize(Self);
        FGXSLProg.EndUseProgramObject;
      end;
      if Assigned(FOnInitializeEx) then
      begin
        FGXSLProg.UseProgramObject;
        FOnInitializeEx(Self, Sender);
        FGXSLProg.EndUseProgramObject;
      end;
      if (not FGXSLProg.ValidateProgram) then
        raise EgxslShaderException.Create(FGXSLProg.InfoLog);
    except
      on E: Exception do
      begin
        Enabled := False;
        HandleFailedInitialization(E.Message);
      end;
    end;
  end;
end;


function TgxslCustomShader.DoUnApply(var rci: TgxRenderContextInfo): Boolean;
begin
  Result := False;
  if Assigned(FOnUnApply) then
    FOnUnApply(Self, Result);
  if not Result then
    FGXSLProg.EndUseProgramObject;
end;

function TgxslCustomShader.ShaderSupported: Boolean;
begin
  Result := True; (*  (GL_ARB_shader_objects and GL_ARB_vertex_program and
             GL_ARB_vertex_shader and GL_ARB_fragment_shader); *)
end;

function TgxslCustomShader.GetActiveAttribs: TgxActiveAttribArray;
var
  LRci: TgxRenderContextInfo;
  i, j: Integer;
  buff: array[0..127] of AnsiChar;
  len: GLsizei;
  max: GLInt;
  glType: GLEnum;
begin
  DoInitialize(LRci, Self);

  SetLength(Result, 16);
  j := 0;
  if FGXSLProg.Handle<>0 then
  begin
    glGetProgramiv(FGXSLProg.Handle, GL_ACTIVE_ATTRIBUTES, @max);
    for i := 0 to 16 - 1 do
    if i<max then
    begin
      glGetActiveAttrib(FGXSLProg.Handle, i, Length(buff), @len, @Result[j].Size,
        @glType, @buff[0]);
      if glType > 0 then
        with Result[j] do
        begin
          case glType of
            GL_FLOAT: AType := GLSLType1F;
            GL_FLOAT_VEC2: AType := GLSLType2F;
            GL_FLOAT_VEC3: AType := GLSLType3F;
            GL_FLOAT_VEC4: AType := GLSLType4F;
            GL_INT: AType := GLSLType1I;
            GL_INT_VEC2: AType := GLSLType2I;
            GL_INT_VEC3: AType := GLSLType3I;
            GL_INT_VEC4: AType := GLSLType4I;
            GL_UNSIGNED_INT: AType := GLSLType1UI;
            GL_UNSIGNED_INT_VEC2: AType := GLSLType2UI;
            GL_UNSIGNED_INT_VEC3: AType := GLSLType3UI;
            GL_UNSIGNED_INT_VEC4: AType := GLSLType4UI;
            GL_BOOL: AType := GLSLType1I;
            GL_BOOL_VEC2: AType := GLSLType2I;
            GL_BOOL_VEC3: AType := GLSLType3I;
            GL_BOOL_VEC4: AType := GLSLType4I;
            GL_FLOAT_MAT2: AType := GLSLTypeMat2F;
            GL_FLOAT_MAT3: AType := GLSLTypeMat3F;
            GL_FLOAT_MAT4: AType := GLSLTypeMat4F;
          end;
          Name := Copy(string(buff), 0, len);
          Location := i;
          Inc(j);
        end;
    end;
  end;
  SetLength(Result, j);
end;

procedure TgxslCustomShader.Assign(Source: TPersistent);
begin
  inherited Assign(Source);

  if Source is TgxslCustomShader then
  begin
    FreeAndNil(FGXSLProg); //just free the handle for it to be recreated on next initialization
  end;
end;

procedure TgxslCustomShader.DoFinalize;
begin
  inherited;
  if Assigned(FGXSLProg) then
    FGXSLProg.NotifyChangesOfData;
end;

function TgxslCustomShader.GetGXSLProg: TgxProgramHandle;
begin
  Result := FGXSLProg;
end;

function TgxslCustomShader.GetParam(
  const Index: string): TgxslShaderParameter;
begin
  FParam.FParameterID := FGXSLProg.GetUniformLocation(Index);
  Result := FParam;
end;

function TgxslCustomShader.GetDirectParam(
  const Index: Cardinal): TgxslShaderParameter;
begin
  FParam.FParameterID := Index;
  Result := FParam;
end;

function TgxslCustomShader.GetCurrentParam: TgxslShaderParameter;
begin
  Result := FParam;
end;

constructor TgxslCustomShader.Create(AOwner: TComponent);
begin
  inherited;
  FGXSLProg := TgxProgramHandle.Create;
  FParam := TgxslShaderParameter.Create;
  FParam.FGXSLProg := FGXSLProg;
  FActiveVarying := TStringList.Create;
  TStringList(FActiveVarying).OnChange := OnChangeActiveVarying;
  FTransformFeedBackMode := tfbmInterleaved;
end;

destructor TgxslCustomShader.Destroy;
begin
  FreeAndNil(FGXSLProg);
  FreeAndNil(FParam);
  FreeAndNil(FActiveVarying);
  inherited;
end;

procedure TgxslCustomShader.SetActiveVarying(const Value: TStrings);
begin
  FActiveVarying.Assign(Value);
  NotifyChange(Self);
end;

procedure TgxslCustomShader.SetTransformFeedBackMode(const Value: TgxTransformFeedBackMode);
begin
  if Value <> FTransformFeedBackMode then
  begin
    FTransformFeedBackMode := Value;
    NotifyChange(Self);
  end;
end;

procedure TgxslCustomShader.OnChangeActiveVarying(Sender: TObject);
begin
  NotifyChange(Self);
end;

//------------------------------------------------------------
// TgxslShaderParameter
//------------------------------------------------------------

function TgxslShaderParameter.GetAsCustomTexture(
  const TextureIndex: Integer; TextureTarget: TgxTextureTarget): Cardinal;
begin
  glGetUniformiv(FGXSLProg.Handle, TextureIndex, @Result);
end;

function TgxslShaderParameter.GetAsMatrix2f: TMatrix2f;
begin
  glGetUniformfv(FGXSLProg.Handle, FParameterID, @Result);
end;

function TgxslShaderParameter.GetAsMatrix3f: TMatrix3f;
begin
  glGetUniformfv(FGXSLProg.Handle, FParameterID, @Result);
end;

function TgxslShaderParameter.GetAsMatrix4f: TMatrix4f;
begin
  glGetUniformfv(FGXSLProg.Handle, FParameterID, @Result);
end;

function TgxslShaderParameter.GetAsVector1f: Single;
begin
  glGetUniformfv(FGXSLProg.Handle, FParameterID, @Result);
end;

function TgxslShaderParameter.GetAsVector1i: Integer;
begin
  glGetUniformiv(FGXSLProg.Handle, FParameterID, @Result);
end;

function TgxslShaderParameter.GetAsVector2f: TVector2f;
begin
  glGetUniformfv(FGXSLProg.Handle, FParameterID, @Result);
end;

function TgxslShaderParameter.GetAsVector2i: TVector2i;
begin
  glGetUniformiv(FGXSLProg.Handle, FParameterID, @Result);
end;

function TgxslShaderParameter.GetAsVector3f: TVector3f;
begin
  glGetUniformfv(FGXSLProg.Handle, FParameterID, @Result);
end;

function TgxslShaderParameter.GetAsVector3i: TVector3i;
begin
  glGetUniformiv(FGXSLProg.Handle, FParameterID, @Result);
end;

function TgxslShaderParameter.GetAsVector4f: TVector4f;
begin
  glGetUniformfv(FGXSLProg.Handle, FParameterID, @Result);
end;

function TgxslShaderParameter.GetAsVector4i: TVector4i;
begin
  glGetUniformiv(FGXSLProg.Handle, FParameterID, @Result);
end;

procedure TgxslShaderParameter.SetAsCustomTexture(
  const TextureIndex: Integer; TextureTarget: TgxTextureTarget;
  const Value: Cardinal);
begin
  CurrentContext.gxStates.TextureBinding[TextureIndex, TextureTarget] := Value;
  glUniform1i(FParameterID, TextureIndex);
end;

procedure TgxslShaderParameter.SetAsMatrix2f(const Value: TMatrix2f);
begin
  glUniformMatrix2fv(FParameterID, 1, 1, @Value);
end;

procedure TgxslShaderParameter.SetAsMatrix3f(const Value: TMatrix3f);
begin
  glUniformMatrix3fv(FParameterID, 1, 1, @Value);
end;

procedure TgxslShaderParameter.SetAsMatrix4f(const Value: TMatrix4f);
begin
  glUniformMatrix4fv(FParameterID, 1, 1, @Value);
end;

procedure TgxslShaderParameter.SetAsVector1f(const Value: Single);
begin
  glUniform1f(FParameterID, Value);
end;

procedure TgxslShaderParameter.SetAsVector1i(const Value: Integer);
begin
  glUniform1i(FParameterID, Value);
end;

procedure TgxslShaderParameter.SetAsVector2f(const Value: TVector2f);
begin
  glUniform2f(FParameterID, Value.X, Value.Y);
end;

procedure TgxslShaderParameter.SetAsVector2i(const Value: TVector2i);
begin
  glUniform2i(FParameterID, Value.X, Value.Y);
end;

procedure TgxslShaderParameter.SetAsVector3f(const Value: TVector3f);
begin
  glUniform3f(FParameterID, Value.X, Value.Y, Value.Z);
end;

procedure TgxslShaderParameter.SetAsVector3i(const Value: TVector3i);
begin
  glUniform3i(FParameterID, Value.X, Value.Y, Value.Z);
end;

procedure TgxslShaderParameter.SetAsVector4f(const Value: TVector4f);
begin
  glUniform4f(FParameterID, Value.X, Value.Y, Value.Z, Value.W);
end;

procedure TgxslShaderParameter.SetAsVector4i(const Value: TVector4i);
begin
  glUniform4i(FParameterID, Value.X, Value.Y, Value.Z, Value.W);
end;

function TgxslShaderParameter.GetAsUniformBuffer: GLenum;
begin
  glGetUniformiv(FGXSLProg.Handle, FParameterID, @Result);
end;

function TgxslShaderParameter.GetAsVector1ui: GLuint;
begin
  glGetUniformuiv(FGXSLProg.Handle, FParameterID, @Result);
end;

procedure TgxslShaderParameter.SetAsVector1ui(const Value: GLuint);
begin
  glUniform1ui(FParameterID, Value);
end;

function TgxslShaderParameter.GetAsVector2ui: TVector2ui;
begin
  glGetUniformiv(FGXSLProg.Handle, FParameterID, @Result);
end;

procedure TgxslShaderParameter.SetAsVector2ui(const Value: TVector2ui);
begin
  glUniform2ui(FParameterID, Value.X, Value.Y);
end;

function TgxslShaderParameter.GetAsVector3ui: TVector3ui;
begin
  glGetUniformiv(FGXSLProg.Handle, FParameterID, @Result);
end;

procedure TgxslShaderParameter.SetAsVector3ui(const Value: TVector3ui);
begin
  glUniform3ui(FParameterID, Value.X, Value.Y, Value.Z);
end;

function TgxslShaderParameter.GetAsVector4ui: TVector4ui;
begin
  glGetUniformiv(FGXSLProg.Handle, FParameterID, @Result);
end;

procedure TgxslShaderParameter.SetAsVector4ui(const Value: TVector4ui);
begin
  glUniform4ui(FParameterID, Value.X, Value.Y, Value.Z, Value.W);
end;

procedure TgxslShaderParameter.SetAsUniformBuffer(UBO: Cardinal);
begin
  CurrentContext.gxStates.UniformBufferBinding := UBO;
  glUniformBufferEXT(FGXSLProg.Handle, FParameterID, UBO);
end;

//=======================================================
initialization
//=======================================================

  RegisterClasses([TgxslCustomShader, TgxslShader]);

end.
