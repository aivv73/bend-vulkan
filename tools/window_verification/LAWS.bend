import Base
import ./pixels.bend as Pixels

law capture_excludes_padding:
  for +width: U32
  for +height: U32
  for pixels: Array<U32>
  {Pixels.frame(width,height,pixels) == Pixels.Frame{width,height,List.take(&2,U32,Pixels.flatten(pixels,[]),U32.to_nat(U32.mul(width,height)))} : Pixels.Frame}

law exact_comparison_checks_extent_and_every_pixel:
  for aw: U32
  for ah: U32
  for ap: List<&2,U32>
  for bw: U32
  for bh: U32
  for bp: List<&2,U32>
  {Pixels.equal(Pixels.Frame{aw,ah,ap},Pixels.Frame{bw,bh,bp}) == (U32.is_eq(aw,bw) && U32.is_eq(ah,bh) && Pixels.equal_pixels(ap,bp)) : Bool}

law empty_pixel_sequences_agree:
  {Pixels.equal_pixels([],[]) == True{} : Bool}

law missing_pixels_disagree:
  for pixel: U32
  for rest: List<&2,U32>
  {Pixels.equal_pixels(pixel <> rest,[]) == False{} : Bool}

law appearance_requires_both_faces_and_five_colors:
  for warm: Bool
  for cool: Bool
  for count: U32
  for center: U32
  {Pixels.appearance(Pixels.Summary{warm,cool,count},center) == (warm && cool && U32.is_ge(count,5) && Pixels.center_rgb(Pixels.rgb(center))) : Bool}
