package axi_uvm_pkg;

  import uvm_pkg::*;
  import axi_pkg::*;

  `include "uvm_macros.svh"

  `include "axi_transaction.sv"
  `include "axi_monitor.sv"
  `include "soc_scoreboard.sv"
  `include "soc_env.sv"
  `include "soc_base_test.sv"

endpackage