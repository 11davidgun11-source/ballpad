#include "ballpad_pad.h"
#include <stdio.h>
#include <string.h>
int main(void) {
  BallPadStatus s = {0};
  s.button = 0x0100;
  s.err = 0;
  ballpad_pad_set(0, &s);
  BallPadStatus out = {0};
  ballpad_pad_get(0, &out);
  if (out.button != 0x0100 || out.err != 0) {
    fprintf(stderr, "FAIL button=%04x err=%d\n", out.button, out.err);
    return 1;
  }
  BallPadStatus controller = {0};
  controller.button = 0x0200;
  controller.stickX = -100;
  controller.triggerRight = 220;
  controller.err = 0;
  s.stickX = 80;
  s.triggerRight = 30;
  ballpad_pad_set(0, &s);
  ballpad_pad_set_controller(0, &controller);
  ballpad_pad_get(0, &out);
  if (out.button != 0x0300 || out.stickX != -100 ||
      out.triggerRight != 220 || out.err != 0) {
    fprintf(stderr, "FAIL merge button=%04x stick=%d trigger=%u err=%d\n",
            out.button, out.stickX, out.triggerRight, out.err);
    return 1;
  }
  ballpad_pad_clear_controller(0);
  ballpad_pad_get(0, &out);
  if (out.button != 0x0100 || out.stickX != 80 || out.triggerRight != 30) {
    fprintf(stderr, "FAIL controller clear button=%04x stick=%d trigger=%u\n",
            out.button, out.stickX, out.triggerRight);
    return 1;
  }
  printf("PASS ballpad_pad thread-safe touch/controller merge\n");
  return 0;
}
