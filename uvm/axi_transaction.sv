class axi_transaction extends uvm_sequence_item;

  typedef enum {
    AXI_WRITE,
    AXI_READ
  } axi_txn_kind_e;

  axi_txn_kind_e kind;

  rand bit [3:0]  id;
  rand bit [31:0] addr;
  rand bit [31:0] data;
  rand bit [7:0]  len;
  rand bit        last;

  bit [1:0] resp;

  `uvm_object_utils_begin(axi_transaction)
    `uvm_field_enum(axi_txn_kind_e, kind, UVM_ALL_ON)
    `uvm_field_int(id,   UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_int(data, UVM_ALL_ON)
    `uvm_field_int(len,  UVM_ALL_ON)
    `uvm_field_int(last, UVM_ALL_ON)
    `uvm_field_int(resp, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "axi_transaction");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("kind=%s id=%0d addr=0x%08h data=0x%08h len=%0d last=%0b resp=%0d",
                     kind.name(), id, addr, data, len, last, resp);
  endfunction

endclass