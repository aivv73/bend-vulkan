for (const name of [CID(start), CID(status), CID(find), CID(control), CID(open_capture)]) {
  io_eff(name, () => io_fail(95, "Build the window verifier natively: bend examples/verify_window.bend -o build/verify-window"));
}
io_eff(CID(close_capture), () => ({$: CID(Unit)}));
