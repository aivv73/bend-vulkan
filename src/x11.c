// Linux X11 window effects share the checked registry with native.c.
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/Xatom.h>
#include <vulkan/vulkan_xlib.h>
#include <poll.h>

#define BV_XLIB_FUNCTIONS(X) \
  X(XInitThreads) X(XLockDisplay) X(XUnlockDisplay) X(XOpenDisplay) X(XCloseDisplay) X(XCreateSimpleWindow) X(XDestroyWindow) \
  X(XDefaultScreen) X(XRootWindow) X(XBlackPixel) X(XStoreName) X(XSelectInput) \
  X(XInternAtom) X(XChangeProperty) X(XSetWMProtocols) X(XMapWindow) X(XFlush) X(XPending) X(XNextEvent) \
  X(XLookupKeysym) X(XNextRequest) X(XQueryPointer) X(XGrabPointer) X(XUngrabPointer) X(XWarpPointer) X(XConnectionNumber) \
  X(XCreateBitmapFromData) X(XCreatePixmapCursor) X(XFreePixmap) X(XFreeCursor) X(XUndefineCursor)
typedef enum { BV_POINTER_READY, BV_POINTER_WARPING } BvPointerPhase;
typedef struct { int x,y; unsigned long floor,serial; BvPointerPhase phase; } BvPointer;
typedef struct {
  BvWindowContext base;
  void* library;
  Display* display;
  Window window;
  Atom close;
  Cursor cursor;
  uint32_t width,height;
  bool mapped,focused,captured;
  BvPointer pointer;
#define BV_XFIELD(name) __typeof__(&name) name;
  BV_XLIB_FUNCTIONS(BV_XFIELD)
#undef BV_XFIELD
} BvWindow;
static void bv_pointer_warp_locked(BvWindow* window) {
  int x=window->width/2,y=window->height/2;
  if(window->pointer.phase==BV_POINTER_READY && (window->pointer.x!=x || window->pointer.y!=y)) {
    window->pointer.serial=window->XNextRequest(window->display);window->pointer.phase=BV_POINTER_WARPING;
    window->XWarpPointer(window->display,None,window->window,0,0,0,0,x,y);
  }
}
static void bv_pointer_warp(BvWindow* window) {
  window->XLockDisplay(window->display);bv_pointer_warp_locked(window);window->XUnlockDisplay(window->display);
}
static int bv_pointer_reset(BvWindow* window) {
  Window root,child;int rx,ry,x,y;unsigned state;
  window->XLockDisplay(window->display);
  int valid=window->XQueryPointer(window->display,window->window,&root,&child,&rx,&ry,&x,&y,&state);
  if(valid) {
    window->pointer=(BvPointer){.x=x,.y=y,.floor=window->XNextRequest(window->display)-1,.phase=BV_POINTER_READY};
    bv_pointer_warp_locked(window);
  }
  window->XUnlockDisplay(window->display);return valid;
}
static void bv_capture_off(BvWindow* window) {
  if (window->captured) {
    window->XUngrabPointer(window->display,CurrentTime);
    if(window->window)window->XUndefineCursor(window->display,window->window);
    window->captured=false;window->pointer.phase=BV_POINTER_READY;window->XFlush(window->display);
  }
}
static void bv_window_destroy_impl(BvRow* row) {
  BvWindow* window=row->context;bv_capture_off(window);
  window->XFreeCursor(window->display,window->cursor);
  if(window->window)window->XDestroyWindow(window->display,window->window);
  window->XCloseDisplay(window->display);dlclose(window->library);free(window);bv_remove(row);
}
#ifdef CID(Entry.open_window)
static Term bv_open_window(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_ENTRY);uint64_t length=0;char* title=io_cstr(e,f[1],&length);
  uint32_t width=f[2],height=f[3];
  if (!owner || io_nul(title,length) || !width || !height || width>16384 || height>16384) {free(title);return io_fail(e,BV_ARGUMENT,"window owner, title or extent");}
  BvWindow* window=calloc(1,sizeof(*window));BvRow* row=window ? bv_add(BV_WINDOW,owner) : NULL;
  if (!row) {free(title);free(window);return io_fail(e,BV_LIMIT,"window metadata");}
  window->base.destroy=bv_window_destroy_impl;
  window->library=dlopen("libX11.so.6",RTLD_NOW|RTLD_LOCAL);int complete=window->library!=NULL;
#define BV_XLOAD(name) window->name=window->library ? (__typeof__(window->name))dlsym(window->library,#name) : NULL;complete &= window->name!=NULL;
  BV_XLIB_FUNCTIONS(BV_XLOAD)
#undef BV_XLOAD
  if (!complete || !window->XInitThreads() || !(window->display=window->XOpenDisplay(NULL))) {
    if(window->library) dlclose(window->library);free(title);free(window);bv_remove(row);return io_fail(e,BV_ARGUMENT,"X11 display or dispatch unavailable");
  }
  int screen=window->XDefaultScreen(window->display);
  window->window=window->XCreateSimpleWindow(window->display,window->XRootWindow(window->display,screen),0,0,width,height,0,0,window->XBlackPixel(window->display,screen));
  window->width=width;window->height=height;
  window->XStoreName(window->display,window->window,title);free(title);
  window->XSelectInput(window->display,window->window,StructureNotifyMask|FocusChangeMask|KeyPressMask|KeyReleaseMask|ButtonPressMask|ButtonReleaseMask|PointerMotionMask|ExposureMask);
  window->close=window->XInternAtom(window->display,"WM_DELETE_WINDOW",False);
  window->XSetWMProtocols(window->display,window->window,&window->close,1);
  unsigned long pid=(unsigned long)getpid();
  window->XChangeProperty(window->display,window->window,window->XInternAtom(window->display,"_NET_WM_PID",False),XA_CARDINAL,32,PropModeReplace,(unsigned char*)&pid,1);
  char blank[1]={0};Pixmap pixmap=window->XCreateBitmapFromData(window->display,window->window,blank,1,1);XColor black={0};
  window->cursor=window->XCreatePixmapCursor(window->display,pixmap,pixmap,&black,&black,0,0);window->XFreePixmap(window->display,pixmap);
  window->XMapWindow(window->display,window->window);window->XFlush(window->display);
  row->context=window;return io_done(e,term_pak(CID(NativeWindow),row->id));
}
#endif
#ifdef CID(NativeWindow.capture)
static Term bv_window_capture(Env e,Term* f,IoWork* w) {
  BvRow* row=bv_get(bv_key(e,f[0]),BV_WINDOW);if(!row)return io_fail(e,BV_INVALID,"invalid window");
  BvWindow* window=row->context;
  if(term_aux(f[1])!=CID(True)) {bv_capture_off(window);return io_done(e,term_pak(CID(False),0));}
  if(!window->focused || !window->mapped)return io_done(e,term_pak(CID(False),0));
  if(!window->captured) {
    int result=window->XGrabPointer(window->display,window->window,False,ButtonPressMask|ButtonReleaseMask|PointerMotionMask,GrabModeAsync,GrabModeAsync,window->window,window->cursor,CurrentTime);
    if(result!=GrabSuccess)return io_done(e,term_pak(CID(False),0));
    window->captured=true;
    if(!bv_pointer_reset(window)) {bv_capture_off(window);return io_done(e,term_pak(CID(False),0));}
    window->XFlush(window->display);
  }
  return io_done(e,term_pak(CID(True),0));
}
#endif
#ifdef CID(NativeWindow.close)
static Term bv_window_close(Env e,Term* f,IoWork* w) {
  BvRow* row=bv_get(bv_key(e,f[0]),BV_WINDOW);if(!row)return io_fail(e,BV_INVALID,"invalid window");
  if(bv_referenced(row))return io_fail(e,BV_LIFETIME,"window retained by surface");
  bv_destroy_window(row);return bv_ok(e);
}
#endif
#ifdef CID(NativeWindow.poll)
static uint32_t bv_window_coordinate(int position,uint32_t limit) {
  return !limit || position<0 ? 0 : (uint32_t)position>=limit ? limit-1 : (uint32_t)position;
}
static Term bv_bool(bool value) {return value ? 1 : 0;}
static uint32_t bv_release_controls(Env e,Term* events,uint32_t count) {
  for(const char* key="wsadqe";*key;key++)events[count++]=io_node(e,CID(Key),(uint32_t)*key,0);
  Term p[]={0,0,1,0};events[count++]=bv_node(e,CID(Mouse),4,p);return count;
}
static Term bv_window_poll(Env e,Term* f,IoWork* w) {
  BvRow* row=bv_get(bv_key(e,f[0]),BV_WINDOW);uint32_t timeout=f[1];
  if(!row)return io_fail(e,BV_INVALID,"invalid window");
  if(timeout>1000)return io_fail(e,BV_ARGUMENT,"window wait exceeds 1000 ms");
  BvWindow* window=row->context;
  if(!window->XPending(window->display) && timeout) {struct pollfd fd={window->XConnectionNumber(window->display),POLLIN,0};poll(&fd,1,(int)timeout);}
  Term events[4096];uint32_t count=0;
  while(count<4080 && window->XPending(window->display)) {
    XEvent event;window->XNextEvent(window->display,&event);Term value=0;
    switch(event.type) {
      case ConfigureNotify:
        window->width=event.xconfigure.width;window->height=event.xconfigure.height;
        if(window->captured && !bv_pointer_reset(window)) {bv_capture_off(window);count=bv_release_controls(e,events,count);}
        break;
      case MapNotify:window->mapped=true;break;
      case UnmapNotify:window->mapped=false;bv_capture_off(window);count=bv_release_controls(e,events,count);break;
      case FocusIn:window->focused=true;break;
      case FocusOut:
        window->focused=false;bv_capture_off(window);
        count=bv_release_controls(e,events,count);break;
      case ClientMessage:if((Atom)event.xclient.data.l[0]==window->close)value=term_pak(CID(Close),0);break;
      case DestroyNotify:window->window=0;window->mapped=false;window->focused=false;window->captured=false;value=term_pak(CID(Close),0);break;
      case KeyPress:case KeyRelease: {
        KeySym key=window->XLookupKeysym(&event.xkey,0);uint32_t code=key==XK_Escape ? 27 : key<=255 ? (uint32_t)key : 0;
        if(code)value=io_node(e,CID(Key),code,bv_bool(event.type==KeyPress));break;
      }
      case ButtonPress:case ButtonRelease: {
        unsigned button=event.xbutton.button;
        if(button==Button1 || button==Button3 || button==Button2) {
          Term p[]={bv_window_coordinate(event.xbutton.x,window->width),bv_window_coordinate(event.xbutton.y,window->height),button==Button1 ? 0 : button==Button3 ? 1 : 2,bv_bool(event.type==ButtonPress)};value=bv_node(e,CID(Mouse),4,p);
        } else if(button>=4 && button<=7 && event.type==ButtonPress) {
          uint32_t direction=button%2 ? 0xbf800000u : 0x3f800000u;
          Term p[]={bv_window_coordinate(event.xbutton.x,window->width),bv_window_coordinate(event.xbutton.y,window->height),button>5 ? direction : 0,button>5 ? 0 : direction};value=bv_node(e,CID(Scroll),4,p);
        }break;
      }
      case MotionNotify:
        if(window->captured) {
          if(event.xmotion.serial<window->pointer.floor)break;
          if(window->pointer.phase==BV_POINTER_WARPING && event.xmotion.serial>=window->pointer.serial) {
            window->pointer.x=window->width/2;window->pointer.y=window->height/2;window->pointer.phase=BV_POINTER_READY;
          }
          int x=event.xmotion.x,y=event.xmotion.y,dx=x-window->pointer.x,dy=y-window->pointer.y;
          window->pointer.x=x;window->pointer.y=y;
          if(dx || dy) {float fx=dx,fy=dy;uint32_t xb,yb;memcpy(&xb,&fx,4);memcpy(&yb,&fy,4);value=io_node(e,CID(Look),xb,yb);}
        } else value=io_node(e,CID(Move),bv_window_coordinate(event.xmotion.x,window->width),bv_window_coordinate(event.xmotion.y,window->height));
        break;
    }
    if(value)events[count++]=value;
  }
  if(window->captured)bv_pointer_warp(window);
  window->XFlush(window->display);Term list=term_pak(CID(Nil),0);
  while(count)list=io_node(e,CID(Con),events[--count],list);
  Term p[]={window->width,window->height,bv_bool(window->mapped),bv_bool(window->focused),bv_bool(window->captured),list};
  return io_done(e,bv_node(e,CID(WindowSnapshot),6,p));
}
#endif


#ifdef CID(Instance.create_surface)
static Term bv_create_surface(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_INSTANCE),*window=bv_get(bv_key(e,f[1]),BV_WINDOW);
  if(!owner || !window || window->parent!=owner->parent)return io_fail(e,BV_INVALID,"surface window ownership");
  BvInstance* instance=owner->context;
  if(!instance->presentation || !instance->create_surface)return io_fail(e,BV_ARGUMENT,"X11 presentation instance profile required");
  BvRow* row=bv_add(BV_SURFACE,owner);BvDep* dep=row ? malloc(sizeof(*dep)) : NULL;
  if(!dep) {if(row)bv_remove(row);return io_fail(e,BV_LIMIT,"surface metadata");}
  BvWindow* native=window->context;VkXlibSurfaceCreateInfoKHR create={.sType=VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR,.dpy=native->display,.window=native->window};VkSurfaceKHR handle;
  PFN_vkCreateXlibSurfaceKHR create_surface=(PFN_vkCreateXlibSurfaceKHR)instance->create_surface;
  VkResult result=create_surface(instance->handle,&create,NULL,&handle);
  if(result!=VK_SUCCESS) {free(dep);bv_remove(row);return bv_vk_error(e,result,"vkCreateXlibSurfaceKHR");}
  *dep=(BvDep){.role=BV_DEP_WINDOW,.target=window};row->deps=dep;row->handle=(uintptr_t)handle;
  return io_done(e,term_pak(CID(Surface),row->id));
}
#endif

static void __attribute__((constructor)) bv_window_register(void) {
// BEGIN GENERATED WINDOW REGISTRATIONS
#ifdef CID(Entry.open_window)
  io_eff(CID(Entry.open_window), bv_open_window);
#endif
#ifdef CID(NativeWindow.poll)
  io_eff(CID(NativeWindow.poll), bv_window_poll);
#endif
#ifdef CID(NativeWindow.capture)
  io_eff(CID(NativeWindow.capture), bv_window_capture);
#endif
#ifdef CID(NativeWindow.close)
  io_eff(CID(NativeWindow.close), bv_window_close);
#endif
#ifdef CID(Instance.create_surface)
  io_eff(CID(Instance.create_surface), bv_create_surface);
#endif
// END GENERATED WINDOW REGISTRATIONS
}
