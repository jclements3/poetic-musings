#include <cstdlib>

#include <verilated.h>

#include "Vpm_regfile.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);

  Vpm_regfile *top = new Vpm_regfile;

  while(!Verilated::gotFinish()) {
    top->eval();
  }

  top->final();

  delete top;

  return EXIT_SUCCESS;
}

