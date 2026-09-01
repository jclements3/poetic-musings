#include <cstdlib>

#include <verilated.h>

#include "Vpm_zones.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);

  Vpm_zones *top = new Vpm_zones;

  while(!Verilated::gotFinish()) {
    top->eval();
  }

  top->final();

  delete top;

  return EXIT_SUCCESS;
}

