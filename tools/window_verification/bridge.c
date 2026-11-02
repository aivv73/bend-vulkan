// Verification-only Linux/X11 boundary, pinned to Bend 2.0.39.
// The capture package reads only BendWin.dpy/win. This connection owns no
// drawable and must be disposed by close_capture, never Base Window.close.
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <sys/wait.h>
#include <spawn.h>
#include <signal.h>
#include <fcntl.h>
extern char **environ;

typedef struct { Display* dpy; Window win; } VerificationCaptureWindow;
static pid_t verification_child;
static unsigned long verification_window;
static int verification_xerror;
static int verification_error(Display* d, XErrorEvent* e) { verification_xerror=e->error_code; return 0; }
static void verification_cleanup(void) {
  if (verification_child > 0) {
    kill(verification_child,SIGKILL);
    while(waitpid(verification_child,NULL,0)<0 && errno==EINTR) {}
    verification_child=0;
  }
}
static Term verification_start(Env e, Term* f, IoWork* work) {
  if(verification_child) return io_fail(e,EBUSY,"verification child already running");
  u64 length=0; char* log=io_cstr(e,f[0],&length);
  if(memchr(log,0,length)) { free(log); return io_fail(e,EINVAL,"invalid log path"); }
  posix_spawn_file_actions_t actions;
  int code=posix_spawn_file_actions_init(&actions);
  if(code) {free(log);return io_fail(e,code,"spawn actions");}
  code=posix_spawn_file_actions_addopen(&actions,STDOUT_FILENO,log,O_CREAT|O_WRONLY|O_TRUNC,0600);
  free(log);
  if(!code) code=posix_spawn_file_actions_adddup2(&actions,STDOUT_FILENO,STDERR_FILENO);
  char* plain[]={"./build/indexed-window",NULL};
  char* validated[]={"env","VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation",
    "VK_LAYER_ENABLES=VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT","./build/indexed-window",NULL};
  bool validation=term_aux(f[1])==CID(True);
  if(!code) code=posix_spawnp(&verification_child,validation?"env":plain[0],&actions,NULL,validation?validated:plain,environ);
  posix_spawn_file_actions_destroy(&actions);
  if(code) {verification_child=0;return io_fail(e,code,"starting indexed window");}
  verification_window=0;
  return io_done(e,(u32)verification_child);
}
static Term verification_status(Env e, Term* f, IoWork* work) {
  if(!verification_child || f[0]!=(u32)verification_child) return io_fail(e,EINVAL,"not the owned child");
  int status; pid_t got=waitpid(verification_child,&status,WNOHANG);
  if(got<0) return io_fail(e,errno,"waitpid");
  if(!got) return io_done(e,term_pak(CID(None),0));
  verification_child=0;
  u32 code=WIFEXITED(status)?WEXITSTATUS(status):128+WTERMSIG(status);
  return io_done(e,io_box(e,CID(Some),code));
}
static Window verification_find(Display* d, Window node, Atom atom, pid_t pid, unsigned depth) {
  if(depth>64) return 0;
  Atom actual; int format; unsigned long count,left; unsigned char* value=NULL;
  int result=XGetWindowProperty(d,node,atom,0,1,False,XA_CARDINAL,&actual,&format,&count,&left,&value);
  bool matches=result==Success && actual==XA_CARDINAL && format==32 && count==1 && *(unsigned long*)value==(unsigned long)pid;
  if(value) XFree(value);
  if(matches) return node;
  Window root,parent,*children=NULL,found=0; unsigned n=0;
  if(XQueryTree(d,node,&root,&parent,&children,&n)) {
    for(unsigned i=0;i<n && !found;i++) found=verification_find(d,children[i],atom,pid,depth+1);
  }
  if(children) XFree(children);
  return found;
}
static Term verification_find_run(Env e, Term* f, IoWork* work) {
  if(!verification_child || f[0]!=(u32)verification_child) return io_fail(e,EINVAL,"not the owned child");
  Display* d=XOpenDisplay(NULL);
  if(!d) return io_fail(e,ENOENT,"cannot open DISPLAY");
  verification_xerror=0; int (*previous)(Display*,XErrorEvent*)=XSetErrorHandler(verification_error);
  Window found=verification_find(d,DefaultRootWindow(d),XInternAtom(d,"_NET_WM_PID",False),verification_child,0);
  XSync(d,False); XCloseDisplay(d); XSetErrorHandler(previous);
  verification_window=found;
  return io_done(e,(u32)found);
}
static Term verification_control(Env e, Term* f, IoWork* work) {
  if(!verification_child || !verification_window || f[0]!=verification_window) return io_fail(e,EINVAL,"not the owned window");
  if(f[1]>2 || (f[1]==0 && (!f[2] || !f[3] || f[2]>4096 || f[3]>4096))) return io_fail(e,EINVAL,"invalid window operation");
  Display* d=XOpenDisplay(NULL);
  if(!d) return io_fail(e,ENOENT,"cannot open DISPLAY");
  verification_xerror=0; int (*previous)(Display*,XErrorEvent*)=XSetErrorHandler(verification_error);
  if(f[1]==0) XResizeWindow(d,f[0],f[2],f[3]);
  if(f[1]==1) XUnmapWindow(d,f[0]);
  if(f[1]==2) {XMapRaised(d,f[0]);XMoveWindow(d,f[0],0,0);}
  XSync(d,False); XCloseDisplay(d); XSetErrorHandler(previous);
  return verification_xerror?io_fail(e,EIO,"X11 control failed"):io_done(e,term_pak(CID(Unit),0));
}
static Term verification_open_capture(Env e, Term* f, IoWork* work) {
  term_sink(e,f[1]);
  term_sink(e,f[2]);
  if(!verification_child || !verification_window || f[0]!=verification_window) return io_fail(e,EINVAL,"not the owned window");
  VerificationCaptureWindow* window=calloc(1,sizeof(*window));
  if(!window) return io_fail(e,ENOMEM,"capture connection");
  window->dpy=XOpenDisplay(NULL); window->win=f[0];
  if(!window->dpy) {free(window);return io_fail(e,ENOENT,"cannot open DISPLAY");}
  return io_done(e,io_hand((intptr_t)window));
}
static Term verification_close_capture(Env e, Term* f, IoWork* work) {
  VerificationCaptureWindow* window=(VerificationCaptureWindow*)(intptr_t)io_hand_v(f[0]);
  XCloseDisplay(window->dpy); free(window);
  return term_pak(CID(Unit),0);
}
static void __attribute__((constructor)) verification_register(void) {
  atexit(verification_cleanup);
  io_eff(CID(start),verification_start);
  io_eff(CID(status),verification_status);
  io_eff(CID(find),verification_find_run);
  io_eff(CID(control),verification_control);
  io_eff(CID(open_capture),verification_open_capture);
  io_eff(CID(close_capture),verification_close_capture);
}
