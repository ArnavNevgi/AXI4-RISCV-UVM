class soc_env extends uvm_env;

  `uvm_component_utils(soc_env)

  axi_monitor cpu_mon;
  axi_monitor dma_mon;
  soc_scoreboard scb;

  function new(string name = "soc_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cpu_mon = axi_monitor::type_id::create("cpu_mon", this);
    dma_mon = axi_monitor::type_id::create("dma_mon", this);
    scb     = soc_scoreboard::type_id::create("scb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    cpu_mon.ap.connect(scb.cpu_imp);
    dma_mon.ap.connect(scb.dma_imp);
  endfunction

endclass