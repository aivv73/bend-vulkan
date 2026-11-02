import Base

type Frame is Data:
  Frame{width: U32, height: U32, pixels: List<&2,U32>}
type ColorCount is Data:
  ColorCount{color: U32, count: U32}
type Summary is Data:
  Summary{warm: Bool, cool: Bool, substantial: U32}

def flatten(a: Array<U32>, tail: List<&2,U32>) -> List<&2,U32>:
  match a:
    case ALeaf{x}: x <> tail
    case ANode{left,right}: flatten(left,flatten(right,tail))

def frame(+w: U32, +h: U32, pixels: Array<U32>) -> Frame:
  Frame{w,h,List.take(&2,U32,flatten(pixels,[]),U32.to_nat(U32.mul(w,h)))}

def rgb(+pixel: U32) -> U32 & (U32 & U32):
  (U32.and(U32.div(pixel,65536),255),(U32.and(U32.div(pixel,256),255),U32.and(pixel,255)))

def warm_rgb(value: U32 & (U32 & U32)) -> Bool:
  (r,(g,b)) = value
  +r : U32 = r
  U32.is_gt(r,150) && U32.is_gt(U32.mul(r,100),U32.mul(g,115)) && U32.is_gt(U32.mul(r,2),U32.mul(b,3))

def cool_rgb(value: U32 & (U32 & U32)) -> Bool:
  (r,(g,b)) = value
  +g : U32 = g
  U32.is_gt(g,100) && U32.is_gt(U32.mul(g,2),U32.mul(r,3))

def center_rgb(value: U32 & (U32 & U32)) -> Bool:
  (r,(g,b)) = value
  +r : U32 = r
  +g : U32 = g
  (U32.is_gt(r,150) && U32.is_gt(U32.mul(r,2),U32.mul(b,3))) || (U32.is_gt(g,100) && U32.is_gt(U32.mul(g,2),U32.mul(r,3)))

def bump_match(same: Bool, pixel: U32, color: U32, count: U32, rest: List<&2,ColorCount>, updated: List<&2,ColorCount>) -> List<&2,ColorCount>:
  match same:
    case True{}: ColorCount{color,U32.inc(count)} <> rest
    case False{}: ColorCount{color,count} <> updated

def bump(+pixel: U32, counts: List<&2,ColorCount>) -> List<&2,ColorCount>:
  match counts:
    case Nil{}: [ColorCount{pixel,1}]
    case ColorCount{+color,+count} <> +rest:
      bump_match(U32.is_eq(pixel,color),pixel,color,count,rest,bump(pixel,rest))

def histogram(pixels: List<&2,U32>, counts: List<&2,ColorCount>) -> List<&2,ColorCount>:
  match pixels:
    case Nil{}: counts
    case pixel <> rest: histogram(rest,bump(pixel,counts))

def summarize_color(+color: U32, count: U32, summary: Summary) -> Summary:
  Summary{warm,cool,n} = summary
  +large = U32.is_gt(count,100)
  Summary{warm || (large && warm_rgb(rgb(color))),cool || (large && cool_rgb(rgb(color))),U32.add(n,Bool.to_u32(large))}

def summarize(counts: List<&2,ColorCount>) -> Summary:
  match counts:
    case Nil{}: Summary{False{},False{},0}
    case ColorCount{+color,count} <> rest:
      summarize_color(color,count,summarize(rest))

def center(pixels: List<&2,U32>, index: Nat) -> U32:
  match pixels index:
    case Nil{} _: 0
    case pixel <> rest 0n: pixel
    case pixel <> rest 1n+previous: center(rest,previous)

def appearance(summary: Summary, center: U32) -> Bool:
  Summary{warm,cool,count} = summary
  warm && cool && U32.is_ge(count,5) && center_rgb(rgb(center))

def rendered(value: Frame) -> Bool:
  Frame{+w,h,+pixels} = value
  appearance(summarize(histogram(pixels,[])),center(pixels,U32.to_nat(U32.add(U32.mul(U32.div(h,2),w),U32.div(w,2)))))

def equal_pixels(a: List<&2,U32>, b: List<&2,U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: U32.is_eq(x,y) && equal_pixels(xs,ys)
    case _ _: False{}

def equal(a: Frame, b: Frame) -> Bool:
  Frame{aw,ah,ap} = a
  Frame{bw,bh,bp} = b
  U32.is_eq(aw,bw) && U32.is_eq(ah,bh) && equal_pixels(ap,bp)

def extent(value: Frame, w: U32, h: U32) -> Bool:
  Frame{aw,ah,pixels} = value
  U32.is_eq(aw,w) && U32.is_eq(ah,h)

def prepend_rgb(rgb: U32 & (U32 & U32), rest: List<&2,U32>) -> List<&2,U32>:
  (r,(g,b)) = rgb
  r <> g <> b <> rest

def bytes(pixels: List<&2,U32>) -> List<&2,U32>:
  match pixels:
    case Nil{}: []
    case pixel <> rest:
      prepend_rgb(rgb(pixel),bytes(rest))
