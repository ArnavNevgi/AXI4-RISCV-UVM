class soc_base_test extends uvm_test;

  `uvm_component_utils(soc_base_test)

  soc_env env;

  function new(string name = "soc_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    env = soc_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    `uvm_info("SOC_TEST", "Starting passive UVM SoC test", UVM_LOW)

    // Let the Verilog testbench/DUT run.
    #5000ns;

    `uvm_info("SOC_TEST", "Ending passive UVM SoC test", UVM_LOW)

    phase.drop_objection(this);
  endtask

endclass