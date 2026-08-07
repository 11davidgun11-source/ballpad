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
  printf("PASS ballpad_pad A inject storage\n");
  return 0;
}
