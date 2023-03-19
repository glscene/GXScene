//
// The graphics engine GXScene https://github.com/glscene
//
unit GLX.EllipseCollision;

(* Ellipsoid collision functions (mainly used by DCE) *)

interface

{$I Scena.inc}

uses
  Scena.VectorGeometry,
  GLX.Octree,
  GLX.VectorLists,
  Scena.VectorTypes;

type
  TECPlane = class
  public
    Equation: array [0 .. 3] of Single;
    Origin: TAffineVector;
    Normal: TAffineVector;
    procedure MakePlane(const nOrigin, nNormal: TAffineVector); overload;
    procedure MakePlane(const p1, p2, p3: TAffineVector); overload;
    function isFrontFacingTo(const Direction: TAffineVector): Boolean;
    function signedDistanceTo(const Point: TAffineVector): Single;
  end;

  // Object collision properties
  TECObjectInfo = record
    AbsoluteMatrix: TMatrix4f;
    Solid: Boolean;
    IsDynamic: Boolean;
    ObjectID: Integer;
  end;

  TECTriangle = record
    p1, p2, p3: TAffineVector;
  end;

  TECTriMesh = record
    Triangles: Array of TECTriangle;
    ObjectInfo: TECObjectInfo;
  end;

  TECTriMeshList = Array of TECTriMesh;

  TECFreeForm = record
    OctreeNodes: array of POctreeNode;
    triangleFiler: ^TgxAffineVectorList;
    InvertedNormals: Boolean;
    ObjectInfo: TECObjectInfo;
  end;

  TECFreeFormList = Array of TECFreeForm;

  TECColliderShape = (csEllipsoid, csPoint);

  TECCollider = record
    Position: TAffineVector;
    Radius: TAffineVector;
    Shape: TECColliderShape;
    ObjectInfo: TECObjectInfo;
  end;

  TECColliderList = Array of TECCollider;

  TECContact = record
    // Generated by the collision procedure
    Position: TAffineVector;
    SurfaceNormal: TAffineVector;
    Distance: Single;
    // Collider data
    ObjectInfo: TECObjectInfo;
  end;

  TECContactList = Array of TECContact;

  TECCollisionPacket = record
    // Information about the move being requested: (in eSpace)
    Velocity: TAffineVector;
    NormalizedVelocity: TAffineVector;
    BasePoint: TAffineVector;
    // Hit information
    FoundCollision: Boolean;
    NearestDistance: Single;
    NearestObject: Integer;
    IntersectionPoint: TAffineVector;
    IntersectionNormal: TAffineVector;
  end;

  TECMovePack = record
    // List of closest triangles
    TriMeshes: TECTriMeshList;
    // List of freeform octree nodes
    Freeforms: TECFreeFormList;
    // List of other colliders (f.i. ellipsoids)
    Colliders: TECColliderList;
    // Movement params
    Position: TAffineVector;
    Velocity: TAffineVector;
    Gravity: TAffineVector;
    Radius: TAffineVector;
    ObjectInfo: TECObjectInfo;
    CollisionRange: Single; // Stores the range where objects may collide
    // Internal
    UnitScale: Double;
    MaxRecursionDepth: Byte;
    CP: TECCollisionPacket;
    collisionRecursionDepth: Byte;
    // Result
    ResultPos: TAffineVector;
    NearestObject: Integer;
    VelocityCollided: Boolean;
    GravityCollided: Boolean;
    GroundNormal: TAffineVector;
    Contacts: TECContactList end;

    function VectorDivide(const v, divider: TAffineVector): TAffineVector;
    procedure CollideAndSlide(var MP: TECMovePack);
    procedure CollideWithWorld(var MP: TECMovePack; pos, vel: TAffineVector;
      var HasCollided: Boolean);

  const
    cECCloseDistance: Single = 0.005;

    { .$DEFINE DEBUG }

  var
    Debug_tri: Array of TECTriangle;

//=================================================================
implementation
//=================================================================

{$IFDEF DEBUG}

procedure AddDebugTri(p1, p2, p3: TAffineVector);
begin
  SetLength(Debug_tri, Length(Debug_tri) + 1);
  Debug_tri[High(Debug_tri)].p1 := p1;
  Debug_tri[High(Debug_tri)].p2 := p2;
  Debug_tri[High(Debug_tri)].p3 := p3;
end;
{$ENDIF}

// Utility functions

function CheckPointInTriangle(Point, pa, pb, pc: TAffineVector): Boolean;
var
  e10, e20, vp: TAffineVector;
  a, b, c, d, e, ac_bb, x, y, z: Single;
begin
  e10 := VectorSubtract(pb, pa);
  e20 := VectorSubtract(pc, pa);
  a := VectorDotProduct(e10, e10);
  b := VectorDotProduct(e10, e20);
  c := VectorDotProduct(e20, e20);
  ac_bb := (a * c) - (b * b);
  vp := AffineVectorMake(Point.x - pa.x, Point.y - pa.y, Point.z - pa.z);
  d := VectorDotProduct(vp, e10);
  e := VectorDotProduct(vp, e20);
  x := (d * c) - (e * b);
  y := (e * a) - (d * b);
  z := x + y - ac_bb;
  result := ((z < 0) and not((x < 0) or (y < 0)));
end;

function GetLowestRoot(a, b, c, maxR: Single; var Root: Single): Boolean;
var
  determinant: Single;
  sqrtD, r1, r2, temp: Single;
begin
  // No (valid) solutions
  result := false;
  // Check if a solution exists
  determinant := b * b - 4 * a * c;
  // If determinant is negative it means no solutions.
  if (determinant < 0) then
    Exit;
  // calculate the two roots: (if determinant == 0 then
  // x1==x2 but let�s disregard that slight optimization)
  sqrtD := sqrt(determinant);
  if a = 0 then
    a := -0.01; // is this really needed?
  r1 := (-b - sqrtD) / (2 * a);
  r2 := (-b + sqrtD) / (2 * a);
  // Sort so x1 <= x2
  if (r1 > r2) then
  begin
    temp := r2;
    r2 := r1;
    r1 := temp;
  end;
  // Get lowest root:
  if (r1 > 0) and (r1 < maxR) then
  begin
    Root := r1;
    result := true;
    Exit;
  end;
  // It is possible that we want x2 - this can happen
  // if x1 < 0
  if (r2 > 0) and (r2 < maxR) then
  begin
    Root := r2;
    result := true;
    Exit;
  end;
end;

function VectorDivide(const v, divider: TAffineVector): TAffineVector;
begin
  result.x := v.x / divider.x;
  result.y := v.y / divider.y;
  result.z := v.z / divider.z;
end;

procedure VectorSetLength(var v: TAffineVector; Len: Single);
var
  l, l2: Single;
begin
  l2 := v.x * v.x + v.y * v.y + v.z * v.z;
  l := sqrt(l2);
  if l <> 0 then
  begin
    Len := Len / l;
    v.x := v.x * Len;
    v.y := v.y * Len;
    v.z := v.z * Len;
  end;
end;

//-----------------------------------------
// TECPlane
//-----------------------------------------
procedure TECPlane.MakePlane(const nOrigin, nNormal: TAffineVector);
begin
  Normal := nNormal;
  Origin := nOrigin;
  Equation[0] := Normal.x;
  Equation[1] := Normal.y;
  Equation[2] := Normal.z;
  Equation[3] := -(Normal.x * Origin.x + Normal.y * Origin.y + Normal.z *
    Origin.z);
end;

procedure TECPlane.MakePlane(const p1, p2, p3: TAffineVector);
begin
  Normal := CalcPlaneNormal(p1, p2, p3);
  MakePlane(p1, Normal);
end;

function TECPlane.isFrontFacingTo(const Direction: TAffineVector): Boolean;
var
  Dot: Single;
begin
  Dot := VectorDotProduct(Normal, Direction);
  result := (Dot <= 0);
end;

function TECPlane.signedDistanceTo(const Point: TAffineVector): Single;
begin
  result := VectorDotProduct(Point, Normal) + Equation[3];
end;

// Collision detection functions

// Assumes: p1,p2 and p3 are given in ellisoid space:
// Returns true if collided
function CheckTriangle(var MP: TECMovePack; const p1, p2, p3: TAffineVector;
  ColliderObjectInfo: TECObjectInfo; var ContactInfo: TECContact): Boolean;
var
  trianglePlane: TECPlane;
  t0, t1: Double;
  embeddedInPlane: Boolean;
  signedDistToTrianglePlane: Double;
  normalDotVelocity: Single;
  temp: Double;

  collisionPoint: TAffineVector;
  foundCollison: Boolean;
  t: Single;

  planeIntersectionPoint, v: TAffineVector;

  Velocity, base: TAffineVector;
  velocitySquaredLength: Single;
  a, b, c: Single; // Params for equation
  newT: Single;

  edge, baseToVertex: TAffineVector;
  edgeSquaredLength: Single;
  edgeDotVelocity: Single;
  edgeDotBaseToVertex: Single;

  distToCollision: Single;

begin
  result := false;
  // Make the plane containing this triangle.
  trianglePlane := TECPlane.Create;
  trianglePlane.MakePlane(p1, p2, p3);
  // Is triangle front-facing to the velocity vector?
  // We only check front-facing triangles
  // (your choice of course)
  if not(trianglePlane.isFrontFacingTo(MP.CP.NormalizedVelocity)) then
  begin
    trianglePlane.Free;
    Exit;
  end; // }
  // Get interval of plane intersection:
  embeddedInPlane := false;
  // Calculate the signed distance from sphere
  // position to triangle plane
  // V := VectorAdd(MP.CP.basePoint,MP.CP.velocity);
  // signedDistToTrianglePlane := trianglePlane.signedDistanceTo(v);
  signedDistToTrianglePlane := trianglePlane.signedDistanceTo(MP.CP.BasePoint);
  // cache this as we�re going to use it a few times below:
  normalDotVelocity := VectorDotProduct(trianglePlane.Normal, MP.CP.Velocity);

  // if sphere is travelling parrallel to the plane:
  if normalDotVelocity = 0 then
  begin
    if (abs(signedDistToTrianglePlane) >= 1) then
    begin
      // Sphere is not embedded in plane.
      // No collision possible:
      trianglePlane.Free;
      Exit;
    end
    else
    begin
      // sphere is embedded in plane.
      // It intersects in the whole range [0..1]
      embeddedInPlane := true;
      t0 := 0;
      // t1 := 1;
    end;
  end
  else
  begin
    // N dot D is not 0. Calculate intersection interval:
    t0 := (-1 - signedDistToTrianglePlane) / normalDotVelocity;
    t1 := (1 - signedDistToTrianglePlane) / normalDotVelocity;
    // Swap so t0 < t1
    if (t0 > t1) then
    begin
      temp := t1;
      t1 := t0;
      t0 := temp;
    end;

    // Check that at least one result is within range:
    if (t0 > 1) or (t1 < 0) then
    begin
      trianglePlane.Free;
      Exit; // Both t values are outside values [0,1] No collision possible:
    end;
    // Clamp to [0,1]
    if (t0 < 0) then
      t0 := 0;
    if (t0 > 1) then
      t0 := 1;
    // if (t1 < 0) then t1 := 0;
    // if (t1 > 1) then t1 := 1;
  end;

  // OK, at this point we have two time values t0 and t1
  // between which the swept sphere intersects with the
  // triangle plane. If any collision is to occur it must
  // happen within this interval.
  foundCollison := false;
  t := 1;
  // First we check for the easy case - collision inside
  // the triangle. If this happens it must be at time t0
  // as this is when the sphere rests on the front side
  // of the triangle plane. Note, this can only happen if
  // the sphere is not embedded in the triangle plane.
  if (not embeddedInPlane) then
  begin
    planeIntersectionPoint := VectorSubtract(MP.CP.BasePoint,
      trianglePlane.Normal);
    v := VectorScale(MP.CP.Velocity, t0);
    VectorAdd(planeIntersectionPoint, v);
    if CheckPointInTriangle(planeIntersectionPoint, p1, p2, p3) then
    begin
      foundCollison := true;
      t := t0;
      collisionPoint := planeIntersectionPoint;
    end;
  end;
  // if we haven�t found a collision already we�ll have to
  // sweep sphere against points and edges of the triangle.
  // Note: A collision inside the triangle (the check above)
  // will always happen before a vertex or edge collision!
  // This is why we can skip the swept test if the above
  // gives a collision!
  if (not foundCollison) then
  begin
    // some commonly used terms:
    Velocity := MP.CP.Velocity;
    base := MP.CP.BasePoint;
    velocitySquaredLength := VectorNorm(Velocity);
    // velocitySquaredLength := Sqr(VectorLength(velocity));
    // For each vertex or edge a quadratic equation have to
    // be solved. We parameterize this equation as
    // a*t^2 + b*t + c = 0 and below we calculate the
    // parameters a,b and c for each test.
    // Check against points:
    a := velocitySquaredLength;
    // P1
    v := VectorSubtract(base, p1);
    b := 2.0 * (VectorDotProduct(Velocity, v));
    c := VectorNorm(v) - 1.0; // c := Sqr(VectorLength(V)) - 1.0;
    if (GetLowestRoot(a, b, c, t, newT)) then
    begin
      t := newT;
      foundCollison := true;
      collisionPoint := p1;
    end;
    // P2
    v := VectorSubtract(base, p2);
    b := 2.0 * (VectorDotProduct(Velocity, v));
    c := VectorNorm(v) - 1.0; // c := Sqr(VectorLength(V)) - 1.0;
    if (GetLowestRoot(a, b, c, t, newT)) then
    begin
      t := newT;
      foundCollison := true;
      collisionPoint := p2;
    end;
    // P3
    v := VectorSubtract(base, p3);
    b := 2.0 * (VectorDotProduct(Velocity, v));
    c := VectorNorm(v) - 1.0; // c := Sqr(VectorLength(V)) - 1.0;
    if (GetLowestRoot(a, b, c, t, newT)) then
    begin
      t := newT;
      foundCollison := true;
      collisionPoint := p3;
    end;

    // Check against edges:
    // p1 -> p2:
    edge := VectorSubtract(p2, p1);
    baseToVertex := VectorSubtract(p1, base);
    edgeSquaredLength := VectorNorm(edge);
    // edgeSquaredLength := Sqr(VectorLength(edge));
    edgeDotVelocity := VectorDotProduct(edge, Velocity);
    edgeDotBaseToVertex := VectorDotProduct(edge, baseToVertex);
    // Calculate parameters for equation
    a := edgeSquaredLength * -velocitySquaredLength + edgeDotVelocity *
      edgeDotVelocity;
    b := edgeSquaredLength * (2 * VectorDotProduct(Velocity, baseToVertex)) -
      2.0 * edgeDotVelocity * edgeDotBaseToVertex;
    c := edgeSquaredLength * (1 - VectorNorm(baseToVertex)) +
    // (1- Sqr(VectorLength(baseToVertex)) )
      edgeDotBaseToVertex * edgeDotBaseToVertex;

    // Does the swept sphere collide against infinite edge?
    if (GetLowestRoot(a, b, c, t, newT)) then
    begin
      // Check if intersection is within line segment:
      temp := (edgeDotVelocity * newT - edgeDotBaseToVertex) /
        edgeSquaredLength;
      if (temp >= 0) and (temp <= 1) then
      begin
        // intersection took place within segment.
        t := newT;
        foundCollison := true;
        collisionPoint := VectorAdd(p1, VectorScale(edge, temp));
      end;
    end;

    // p1 -> p2:
    edge := VectorSubtract(p3, p2);
    baseToVertex := VectorSubtract(p2, base);
    edgeSquaredLength := VectorNorm(edge);
    // edgeSquaredLength := Sqr(VectorLength(edge));
    edgeDotVelocity := VectorDotProduct(edge, Velocity);
    edgeDotBaseToVertex := VectorDotProduct(edge, baseToVertex);
    // Calculate parameters for equation
    a := edgeSquaredLength * -velocitySquaredLength + edgeDotVelocity *
      edgeDotVelocity;
    b := edgeSquaredLength * (2 * VectorDotProduct(Velocity, baseToVertex)) -
      2.0 * edgeDotVelocity * edgeDotBaseToVertex;
    c := edgeSquaredLength * (1 - VectorNorm(baseToVertex)) +
    // (1- Sqr(VectorLength(baseToVertex)) )
      edgeDotBaseToVertex * edgeDotBaseToVertex;

    // Does the swept sphere collide against infinite edge?
    if (GetLowestRoot(a, b, c, t, newT)) then
    begin
      // Check if intersection is within line segment:
      temp := (edgeDotVelocity * newT - edgeDotBaseToVertex) /
        edgeSquaredLength;
      if (temp >= 0) and (temp <= 1) then
      begin
        // intersection took place within segment.
        t := newT;
        foundCollison := true;
        collisionPoint := VectorAdd(p2, VectorScale(edge, temp));
      end;
    end;

    // p3 -> p1:
    edge := VectorSubtract(p1, p3);
    baseToVertex := VectorSubtract(p3, base);
    edgeSquaredLength := VectorNorm(edge);
    // edgeSquaredLength := Sqr(VectorLength(edge));
    edgeDotVelocity := VectorDotProduct(edge, Velocity);
    edgeDotBaseToVertex := VectorDotProduct(edge, baseToVertex);
    // Calculate parameters for equation
    a := edgeSquaredLength * -velocitySquaredLength + edgeDotVelocity *
      edgeDotVelocity;
    b := edgeSquaredLength * (2 * VectorDotProduct(Velocity, baseToVertex)) -
      2.0 * edgeDotVelocity * edgeDotBaseToVertex;
    c := edgeSquaredLength * (1 - VectorNorm(baseToVertex)) +
    // (1- Sqr(VectorLength(baseToVertex)) )
      edgeDotBaseToVertex * edgeDotBaseToVertex;
    // Does the swept sphere collide against infinite edge?
    if (GetLowestRoot(a, b, c, t, newT)) then
    begin
      // Check if intersection is within line segment:
      temp := (edgeDotVelocity * newT - edgeDotBaseToVertex) /
        edgeSquaredLength;
      if (temp >= 0) and (temp <= 1) then
      begin
        // intersection took place within segment.
        t := newT;
        foundCollison := true;
        collisionPoint := VectorAdd(p3, VectorScale(edge, temp));
      end;
    end;
  end;

  // Set result:
  if foundCollison then
  begin
    // distance to collision: �t� is time of collision
    distToCollision := t * VectorLength(MP.CP.Velocity);
    result := true;

    with ContactInfo do
    begin
      Position := collisionPoint;
      SurfaceNormal := trianglePlane.Normal;
      Distance := distToCollision;
      ObjectInfo := ColliderObjectInfo;
    end;

    // Does this triangle qualify for the closest hit?
    // it does if it�s the first hit or the closest
    if ((MP.CP.FoundCollision = false) or
      (distToCollision < MP.CP.NearestDistance)) and (MP.ObjectInfo.Solid) and
      (ColliderObjectInfo.Solid) then
    begin
      // Collision information nessesary for sliding
      MP.CP.NearestDistance := distToCollision;
      MP.CP.NearestObject := ColliderObjectInfo.ObjectID;
      MP.CP.IntersectionPoint := collisionPoint;
      MP.CP.IntersectionNormal := trianglePlane.Normal;
      MP.CP.FoundCollision := true;
    end;
  end;
  trianglePlane.Free;
end;

function CheckPoint(var MP: TECMovePack; pPos, pNormal: TAffineVector;
  ColliderObjectInfo: TECObjectInfo): Boolean;
var
  newPos: TAffineVector;
  Distance: Single;
  FoundCollision: Boolean;
begin
  newPos := VectorAdd(MP.CP.BasePoint, MP.CP.Velocity);

  // *** Need to check if the ellipsoid is embedded ***
  Distance := VectorDistance(pPos, newPos) - 1; // 1 is the sphere radius

  if Distance < 0 then
    Distance := 0;

  if (VectorNorm(MP.CP.Velocity) >= VectorDistance2(MP.CP.BasePoint, pPos)) then
    Distance := 0;

  FoundCollision := Distance <= (cECCloseDistance * MP.UnitScale);
  // Very small distance

  result := FoundCollision;

  // Set result:
  if FoundCollision then
  begin

    // Add a contact
    SetLength(MP.Contacts, Length(MP.Contacts) + 1);
    with MP.Contacts[High(MP.Contacts)] do
    begin
      Position := pPos;
      ScaleVector(Position, MP.Radius);
      SurfaceNormal := pNormal;
      Distance := Distance;
      ObjectInfo := ColliderObjectInfo;
    end;

    if ((MP.CP.FoundCollision = false) or (Distance < MP.CP.NearestDistance))
      and (MP.ObjectInfo.Solid) and (ColliderObjectInfo.Solid) then
    begin
      // Collision information nessesary for sliding
      MP.CP.NearestDistance := Distance;
      MP.CP.NearestObject := ColliderObjectInfo.ObjectID;
      MP.CP.IntersectionPoint := pPos;
      MP.CP.IntersectionNormal := pNormal;
      MP.CP.FoundCollision := true;
    end;
  end;

end;

function CheckEllipsoid(var MP: TECMovePack; ePos, eRadius: TAffineVector;
  ColliderObjectInfo: TECObjectInfo): Boolean;
var
  newPos, nA, rA, nB, rB, iPoint, iNormal: TAffineVector;
  dist: Single;
begin
  result := false;

  // Check if the new position has passed the ellipse
  if VectorNorm(MP.CP.Velocity) < VectorDistance2(MP.CP.BasePoint, ePos) then
    newPos := VectorAdd(MP.CP.BasePoint, MP.CP.Velocity)
  else
  begin
    nA := VectorScale(VectorNormalize(VectorSubtract(MP.CP.BasePoint,
      ePos)), 1);
    newPos := VectorAdd(ePos, nA);
  end;

  // Find intersection
  nA := VectorNormalize(VectorDivide(VectorSubtract(ePos, newPos), eRadius));
  rA := VectorAdd(newPos, nA);

  nB := VectorNormalize(VectorDivide(VectorSubtract(rA, ePos), eRadius));
  ScaleVector(nB, eRadius);

  // Is colliding?
  dist := VectorDistance(newPos, ePos) - 1 - VectorLength(nB);
  if (dist > cECCloseDistance) then
    Exit;

  rB := VectorAdd(ePos, nB);

  iPoint := rB;
  iNormal := VectorNormalize(VectorDivide(VectorSubtract(newPos, ePos),
    eRadius));

  if dist < 0 then
    dist := 0;

  // Add a contact
  SetLength(MP.Contacts, Length(MP.Contacts) + 1);
  with MP.Contacts[High(MP.Contacts)] do
  begin
    Position := iPoint;
    ScaleVector(Position, MP.Radius);
    SurfaceNormal := iNormal;
    Distance := dist;
    ObjectInfo := ColliderObjectInfo;
  end;

  if ((MP.CP.FoundCollision = false) or (dist < MP.CP.NearestDistance)) and
    (MP.ObjectInfo.Solid) and (ColliderObjectInfo.Solid) then
  begin
    MP.CP.NearestDistance := dist;
    MP.CP.NearestObject := ColliderObjectInfo.ObjectID;
    MP.CP.IntersectionPoint := iPoint;
    MP.CP.IntersectionNormal := iNormal;
    MP.CP.FoundCollision := true;
  end;

  result := true;
end;

procedure CheckCollisionFreeForm(var MP: TECMovePack);
var
  n, i, t, k: Integer;
  p: POctreeNode;
  p1, p2, p3: PAffineVector;
  v1, v2, v3: TAffineVector;
  Collided: Boolean;
  ContactInfo: TECContact;
begin
  // For each freeform
  for n := 0 to High(MP.Freeforms) do
  begin
    // For each octree node
    for i := 0 to High(MP.Freeforms[n].OctreeNodes) do
    begin
      p := MP.Freeforms[n].OctreeNodes[i];
      // for each triangle
      for t := 0 to High(p.TriArray) do
      begin
        k := p.TriArray[t];
        // These are the vertices of the triangle to check
        p1 := @MP.Freeforms[n].triangleFiler^.List[k];
        p2 := @MP.Freeforms[n].triangleFiler^.List[k + 1];
        p3 := @MP.Freeforms[n].triangleFiler^.List[k + 2];

        if not MP.Freeforms[n].InvertedNormals then
        begin
          SetVector(v1, VectorTransform(p1^,
            MP.Freeforms[n].ObjectInfo.AbsoluteMatrix));
          SetVector(v2, VectorTransform(p2^,
            MP.Freeforms[n].ObjectInfo.AbsoluteMatrix));
          SetVector(v3, VectorTransform(p3^,
            MP.Freeforms[n].ObjectInfo.AbsoluteMatrix));
        end
        else
        begin
          SetVector(v1, VectorTransform(p3^,
            MP.Freeforms[n].ObjectInfo.AbsoluteMatrix));
          SetVector(v2, VectorTransform(p2^,
            MP.Freeforms[n].ObjectInfo.AbsoluteMatrix));
          SetVector(v3, VectorTransform(p1^,
            MP.Freeforms[n].ObjectInfo.AbsoluteMatrix));
        end;
{$IFDEF DEBUG}
        AddDebugTri(v1, v2, v3); // @Debug
{$ENDIF}
        // Set the triangles to the ellipsoid space
        v1 := VectorDivide(v1, MP.Radius);
        v2 := VectorDivide(v2, MP.Radius);
        v3 := VectorDivide(v3, MP.Radius);

        Collided := CheckTriangle(MP, v1, v2, v3, MP.Freeforms[n].ObjectInfo,
          ContactInfo);
        // Add a contact
        if Collided then
        begin
          SetLength(MP.Contacts, Length(MP.Contacts) + 1);
          ScaleVector(ContactInfo.Position, MP.Radius);
          MP.Contacts[High(MP.Contacts)] := ContactInfo;
        end;

      end;
    end;

  end; // for n
end;

procedure CheckCollisionTriangles(var MP: TECMovePack);
var
  n, i: Integer;
  p1, p2, p3: TAffineVector;
  Collided: Boolean;
  ContactInfo: TECContact;
begin

  for n := 0 to High(MP.TriMeshes) do
  begin

    for i := 0 to High(MP.TriMeshes[n].Triangles) do
    begin
{$IFDEF DEBUG}
      AddDebugTri(MP.TriMeshes[n].Triangles[i].p1,
        MP.TriMeshes[n].Triangles[i].p2, MP.TriMeshes[n].Triangles[i].p3);
      // @Debug
{$ENDIF}
      // These are the vertices of the triangle to check
      p1 := VectorDivide(MP.TriMeshes[n].Triangles[i].p1, MP.Radius);
      p2 := VectorDivide(MP.TriMeshes[n].Triangles[i].p2, MP.Radius);
      p3 := VectorDivide(MP.TriMeshes[n].Triangles[i].p3, MP.Radius);
      Collided := CheckTriangle(MP, p1, p2, p3, MP.TriMeshes[n].ObjectInfo,
        ContactInfo);
      // Add a contact
      if Collided then
      begin
        SetLength(MP.Contacts, Length(MP.Contacts) + 1);
        ScaleVector(ContactInfo.Position, MP.Radius);
        MP.Contacts[High(MP.Contacts)] := ContactInfo;
      end;
    end;
  end;
end;

procedure CheckCollisionColliders(var MP: TECMovePack);
var
  i: Integer;
  p1, p2: TAffineVector;
begin

  for i := 0 to High(MP.Colliders) do
  begin
    p1 := VectorDivide(MP.Colliders[i].Position, MP.Radius);
    p2 := VectorDivide(MP.Colliders[i].Radius, MP.Radius);
    case MP.Colliders[i].Shape of
      csEllipsoid:
        CheckEllipsoid(MP, p1, p2, MP.Colliders[i].ObjectInfo);
      csPoint:
        CheckPoint(MP, p1, p2, MP.Colliders[i].ObjectInfo);
    end;
  end;
end;

procedure CollideAndSlide(var MP: TECMovePack);
var
  eSpacePosition, eSpaceVelocity: TAffineVector;
begin
  // calculate position and velocity in eSpace
  eSpacePosition := VectorDivide(MP.Position, MP.Radius);
  eSpaceVelocity := VectorDivide(MP.Velocity, MP.Radius);

  // Iterate until we have our final position.
  MP.collisionRecursionDepth := 0;
  CollideWithWorld(MP, eSpacePosition, eSpaceVelocity, MP.VelocityCollided);

  // Add gravity pull:
  // Set the new R3 position (convert back from eSpace to R3
  MP.GroundNormal := NullVector;
  MP.GravityCollided := false;
  if not VectorIsNull(MP.Gravity) then
  begin
    eSpaceVelocity := VectorDivide(MP.Gravity, MP.Radius);
    eSpacePosition := MP.ResultPos;
    MP.collisionRecursionDepth := 0;
    CollideWithWorld(MP, eSpacePosition, eSpaceVelocity, MP.GravityCollided);
    if MP.GravityCollided then
      MP.GroundNormal := MP.CP.IntersectionNormal;
  end;

  // Convert final result back to R3:
  ScaleVector(MP.ResultPos, MP.Radius);
end;

procedure CollideWithWorld(var MP: TECMovePack; pos, vel: TAffineVector;
  var HasCollided: Boolean);
var
  veryCloseDistance: Single;
  destinationPoint, newBasePoint, v: TAffineVector;

  slidePlaneOrigin, slidePlaneNormal: TAffineVector;
  slidingPlane: TECPlane;
  newDestinationPoint, newVelocityVector: TAffineVector;

begin
  // First we set to false (no collision)
  if (MP.collisionRecursionDepth = 0) then
    HasCollided := false;

  veryCloseDistance := cECCloseDistance * MP.UnitScale;
  MP.ResultPos := pos;
  // do we need to worry?
  if (MP.collisionRecursionDepth > MP.MaxRecursionDepth) then
    Exit;

  // Ok, we need to worry:
  MP.CP.Velocity := vel;
  MP.CP.NormalizedVelocity := VectorNormalize(vel);
  MP.CP.BasePoint := pos;
  MP.CP.FoundCollision := false;

  // Check for collision (calls the collision routines)
  CheckCollisionFreeForm(MP);
  CheckCollisionTriangles(MP);
  CheckCollisionColliders(MP);

  // If no collision we just move along the velocity
  if (not MP.CP.FoundCollision) then
  begin
    MP.ResultPos := VectorAdd(pos, vel);
    Exit;
  end;

  // *** Collision occured ***
  if (MP.CP.FoundCollision) then
    HasCollided := true;
  MP.NearestObject := MP.CP.NearestObject;

  // The original destination point
  destinationPoint := VectorAdd(pos, vel);
  newBasePoint := pos;
  // only update if we are not already very close
  // and if so we only move very close to intersection..not
  // to the exact spot.
  if (MP.CP.NearestDistance >= veryCloseDistance) then
  begin
    v := vel;
    VectorSetLength(v, MP.CP.NearestDistance - veryCloseDistance);
    newBasePoint := VectorAdd(MP.CP.BasePoint, v);
    // Adjust polygon intersection point (so sliding
    // plane will be unaffected by the fact that we
    // move slightly less than collision tells us)
    NormalizeVector(v);
    ScaleVector(v, veryCloseDistance);
    SubtractVector(MP.CP.IntersectionPoint, v);
  end;

  // Determine the sliding plane
  slidePlaneOrigin := MP.CP.IntersectionPoint;
  slidePlaneNormal := VectorSubtract(newBasePoint, MP.CP.IntersectionPoint);
  NormalizeVector(slidePlaneNormal);
  slidingPlane := TECPlane.Create;
  slidingPlane.MakePlane(slidePlaneOrigin, slidePlaneNormal);

  v := VectorScale(slidePlaneNormal,
    slidingPlane.signedDistanceTo(destinationPoint));
  newDestinationPoint := VectorSubtract(destinationPoint, v);

  // Generate the slide vector, which will become our new
  // velocity vector for the next iteration
  newVelocityVector := VectorSubtract(newDestinationPoint,
    MP.CP.IntersectionPoint);

  if (MP.CP.NearestDistance = 0) then
  begin
    v := VectorNormalize(VectorSubtract(newBasePoint, MP.CP.IntersectionPoint));
    v := VectorScale(v, veryCloseDistance);
    AddVector(newVelocityVector, v);
  end;

  // Recurse:
  // dont recurse if the new velocity is very small
  if (VectorNorm(newVelocityVector) < Sqr(veryCloseDistance)) then
  begin
    MP.ResultPos := newBasePoint;
    slidingPlane.Free;
    Exit;
  end;
  slidingPlane.Free;

  Inc(MP.collisionRecursionDepth);
  CollideWithWorld(MP, newBasePoint, newVelocityVector, HasCollided);
end;

end.
