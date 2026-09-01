#include <cstdlib>

#include <verilated.h>

#include "Vpm_adc.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);

  Vpm_adc *top = new Vpm_adc;

  while(!Verilated::gotFinish()) {
    top->eval();
  }

  top->final();

  delete top;

  return EXIT_SUCCESS;
}

