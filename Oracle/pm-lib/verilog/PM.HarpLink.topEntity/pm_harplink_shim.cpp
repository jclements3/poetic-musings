#include <cstdlib>

#include <verilated.h>

#include "Vpm_harplink.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);

  Vpm_harplink *top = new Vpm_harplink;

  while(!Verilated::gotFinish()) {
    top->eval();
  }

  top->final();

  delete top;

  return EXIT_SUCCESS;
}

