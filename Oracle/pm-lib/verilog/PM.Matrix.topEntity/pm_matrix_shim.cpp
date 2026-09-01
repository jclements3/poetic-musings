#include <cstdlib>

#include <verilated.h>

#include "Vpm_matrix.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);

  Vpm_matrix *top = new Vpm_matrix;

  while(!Verilated::gotFinish()) {
    top->eval();
  }

  top->final();

  delete top;

  return EXIT_SUCCESS;
}

